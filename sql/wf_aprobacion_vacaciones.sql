/*
  Motor de aprobación multinivel para vacaciones (PromPerú / sector público).
  Fuente del Nivel 1..N-1: jerarquía AC_CostCenter (boss + ParentLevel1/2/3).
  Nivel final: perfil web (p.ej. APROBADOR = RR.HH.).

  No impacta planilla Softland: solo estados P/A/R en PR_SolicitudVacaciones
  y trazabilidad en WF_SolicitudPaso.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.WF_FlujoConfig', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WF_FlujoConfig (
        Id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Company         VARCHAR(4)  NOT NULL CONSTRAINT DF_WF_FlujoConfig_Company DEFAULT (''),
        TipoSolicitud   VARCHAR(20) NOT NULL,
        Orden           INT         NOT NULL,
        TipoAprobador   VARCHAR(30) NOT NULL, -- JEFE_CC_CADENA | ROL_PERFIL
        ProfileCode     VARCHAR(30) NULL,
        Descripcion     VARCHAR(100) NULL,
        Activo          BIT         NOT NULL CONSTRAINT DF_WF_FlujoConfig_Activo DEFAULT (1)
    );
    CREATE UNIQUE INDEX UX_WF_FlujoConfig
        ON dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden);
END
GO

IF OBJECT_ID('dbo.WF_SolicitudPaso', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WF_SolicitudPaso (
        Id               BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Company          VARCHAR(4)   NOT NULL,
        Person           VARCHAR(20)  NOT NULL,
        Line             INT          NOT NULL,
        Nivel            INT          NOT NULL,
        TipoAprobador    VARCHAR(30)  NOT NULL, -- JEFE_CC | ROL_PERFIL
        CostCenter       VARCHAR(20)  NULL,
        CostCenterCode   VARCHAR(20)  NULL,
        AprobadorPerson  VARCHAR(20)  NULL,
        ProfileCode      VARCHAR(30)  NULL,
        Descripcion      VARCHAR(120) NULL,
        Estado           CHAR(1)      NOT NULL CONSTRAINT DF_WF_SolicitudPaso_Estado DEFAULT ('P'),
        UserID           VARCHAR(20)  NULL,
        FechaRespuesta   DATETIME     NULL,
        Observacion      VARCHAR(500) NULL,
        CONSTRAINT UQ_WF_SolicitudPaso UNIQUE (Company, Person, Line, Nivel)
    );
    CREATE INDEX IX_WF_SolicitudPaso_Pendiente
        ON dbo.WF_SolicitudPaso (Company, Estado, TipoAprobador, AprobadorPerson);
END
GO

/* Config global (Company='') para Vacaciones: cadena CC + RRHH */
IF NOT EXISTS (
    SELECT 1 FROM dbo.WF_FlujoConfig
    WHERE Company = '' AND TipoSolicitud = 'VACACIONES' AND Orden = 1
)
BEGIN
    INSERT INTO dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden, TipoAprobador, ProfileCode, Descripcion, Activo)
    VALUES
        ('', 'VACACIONES', 1, 'JEFE_CC_CADENA', NULL,         'Jefe(s) por Centro de Costo / Organigrama', 1),
        ('', 'VACACIONES', 2, 'ROL_PERFIL',     'APROBADOR',  'Gestión de RR.HH. / Personal', 1);
END
GO

/*
  Demo SB03: rellena boss del CC con el BossPerson más frecuente del área;
  si no hay, usa 46618821 (persona presente en la compañía).
  Así el Nivel 1 se resuelve sin asignar personas fijas en el flujo.
*/
IF EXISTS (SELECT 1 FROM dbo.AC_CostCenter WHERE Company = 'SB03')
BEGIN
    ;WITH BossPorCC AS (
        SELECT
            e.CostCenter,
            BossPerson = MAX(NULLIF(LTRIM(RTRIM(e.BossPerson)), ''))
        FROM dbo.PR_Employee e
        WHERE e.Company = 'SB03'
          AND NULLIF(LTRIM(RTRIM(e.BossPerson)), '') IS NOT NULL
        GROUP BY e.CostCenter
    )
    UPDATE cc
    SET boss = COALESCE(
            NULLIF(LTRIM(RTRIM(cc.boss)), ''),
            b.BossPerson,
            '46618821'
        )
    FROM dbo.AC_CostCenter cc
    LEFT JOIN BossPorCC b ON b.CostCenter = cc.CostCenter
    WHERE cc.Company = 'SB03'
      AND NULLIF(LTRIM(RTRIM(ISNULL(cc.boss, ''))), '') IS NULL;
END
GO

/* Listado bandeja: incluye nivel actual y texto de flujo */
CREATE OR ALTER PROCEDURE [dbo].[sp_pr_aprobarvacaciones_web]
(
    @cia VARCHAR(20),
    @person VARCHAR(20),
    @dni VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON;

    IF RTRIM(ISNULL(@person, '')) = '' SET @person = '0';
    IF @dni IS NULL SET @dni = '';

    SELECT
        SY_Person.Person,
        SY_Person.Name,
        ControlYear,
        DateBegin,
        DateEnd,
        PR_SolicitudVacaciones.status,
        ApprovalDate,
        PR_SolicitudVacaciones.Line AS id,
        CAST(NULL AS VARCHAR(255)) AS NombreSustento,
        flujo.nivel_actual,
        flujo.total_niveles,
        flujo.estado_flujo,
        flujo.descripcion_nivel,
        flujo.tipo_aprobador_actual,
        flujo.aprobador_person_actual,
        flujo.profile_code_actual
    FROM PR_SolicitudVacaciones
    INNER JOIN SY_Person
        ON PR_SolicitudVacaciones.Person = SY_Person.Person
       AND PR_SolicitudVacaciones.Company = @cia
    OUTER APPLY (
        SELECT
            nivel_actual = (
                SELECT MIN(p.Nivel)
                FROM dbo.WF_SolicitudPaso p
                WHERE p.Company = PR_SolicitudVacaciones.Company
                  AND p.Person = PR_SolicitudVacaciones.Person
                  AND p.Line = PR_SolicitudVacaciones.Line
                  AND p.Estado = 'P'
            ),
            total_niveles = (
                SELECT COUNT(*)
                FROM dbo.WF_SolicitudPaso p
                WHERE p.Company = PR_SolicitudVacaciones.Company
                  AND p.Person = PR_SolicitudVacaciones.Person
                  AND p.Line = PR_SolicitudVacaciones.Line
            ),
            estado_flujo = (
                SELECT TOP 1
                    CASE
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso x
                            WHERE x.Company = PR_SolicitudVacaciones.Company
                              AND x.Person = PR_SolicitudVacaciones.Person
                              AND x.Line = PR_SolicitudVacaciones.Line
                              AND x.Estado = 'R'
                        ) THEN 'RECHAZADO'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso x
                            WHERE x.Company = PR_SolicitudVacaciones.Company
                              AND x.Person = PR_SolicitudVacaciones.Person
                              AND x.Line = PR_SolicitudVacaciones.Line
                              AND x.Estado = 'P'
                        ) AND EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso x
                            WHERE x.Company = PR_SolicitudVacaciones.Company
                              AND x.Person = PR_SolicitudVacaciones.Person
                              AND x.Line = PR_SolicitudVacaciones.Line
                        ) THEN 'APROBADO'
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso x
                            WHERE x.Company = PR_SolicitudVacaciones.Company
                              AND x.Person = PR_SolicitudVacaciones.Person
                              AND x.Line = PR_SolicitudVacaciones.Line
                              AND x.Estado = 'P'
                        ) THEN 'EN_APROBACION'
                        ELSE NULL
                    END
            ),
            descripcion_nivel = (
                SELECT TOP 1 p.Descripcion
                FROM dbo.WF_SolicitudPaso p
                WHERE p.Company = PR_SolicitudVacaciones.Company
                  AND p.Person = PR_SolicitudVacaciones.Person
                  AND p.Line = PR_SolicitudVacaciones.Line
                  AND p.Estado = 'P'
                ORDER BY p.Nivel
            ),
            tipo_aprobador_actual = (
                SELECT TOP 1 p.TipoAprobador
                FROM dbo.WF_SolicitudPaso p
                WHERE p.Company = PR_SolicitudVacaciones.Company
                  AND p.Person = PR_SolicitudVacaciones.Person
                  AND p.Line = PR_SolicitudVacaciones.Line
                  AND p.Estado = 'P'
                ORDER BY p.Nivel
            ),
            aprobador_person_actual = (
                SELECT TOP 1 p.AprobadorPerson
                FROM dbo.WF_SolicitudPaso p
                WHERE p.Company = PR_SolicitudVacaciones.Company
                  AND p.Person = PR_SolicitudVacaciones.Person
                  AND p.Line = PR_SolicitudVacaciones.Line
                  AND p.Estado = 'P'
                ORDER BY p.Nivel
            ),
            profile_code_actual = (
                SELECT TOP 1 p.ProfileCode
                FROM dbo.WF_SolicitudPaso p
                WHERE p.Company = PR_SolicitudVacaciones.Company
                  AND p.Person = PR_SolicitudVacaciones.Person
                  AND p.Line = PR_SolicitudVacaciones.Line
                  AND p.Estado = 'P'
                ORDER BY p.Nivel
            )
    ) flujo
    WHERE (@person = '0' OR PR_SolicitudVacaciones.Person = @person)
      AND (
            @dni = ''
            OR SY_Person.Person LIKE '%' + @dni + '%'
            OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
          )
    ORDER BY 2, DateBegin;
END
GO
