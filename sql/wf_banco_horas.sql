/*
  Banco de Horas / Compensación:
  - CA_SobretiempoSolicitud  (crédito, WF SOBRETIEMPO)
  - CA_GoceCompensacion      (débito/goce, WF GOCE_COMP)
  - CA_BancoHorasMov         (libro: solo movimientos efectivos)
  - Bandeja unificada: sp_ca_aprobar_compensaciones_web
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* WF config */
IF NOT EXISTS (
    SELECT 1 FROM dbo.WF_FlujoConfig
    WHERE Company = '' AND TipoSolicitud = 'SOBRETIEMPO' AND Orden = 1
)
BEGIN
    INSERT INTO dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden, TipoAprobador, ProfileCode, Descripcion, Activo)
    VALUES
        ('', 'SOBRETIEMPO', 1, 'JEFE_CC_CADENA', NULL,        'Jefe(s) por Centro de Costo / Organigrama', 1),
        ('', 'SOBRETIEMPO', 2, 'ROL_PERFIL',     'APROBADOR', 'Gestión de RR.HH. / Personal', 1);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.WF_FlujoConfig
    WHERE Company = '' AND TipoSolicitud = 'GOCE_COMP' AND Orden = 1
)
BEGIN
    INSERT INTO dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden, TipoAprobador, ProfileCode, Descripcion, Activo)
    VALUES
        ('', 'GOCE_COMP', 1, 'JEFE_CC_CADENA', NULL,        'Jefe(s) por Centro de Costo / Organigrama', 1),
        ('', 'GOCE_COMP', 2, 'ROL_PERFIL',     'APROBADOR', 'Gestión de RR.HH. / Personal', 1);
END
GO

/* Solicitud de sobretiempo */
IF OBJECT_ID('dbo.CA_SobretiempoSolicitud', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_SobretiempoSolicitud (
        Company          VARCHAR(4)    NOT NULL,
        Person           VARCHAR(20)   NOT NULL,
        Line             INT           NOT NULL,
        Fecha            DATE          NOT NULL,
        HoraInicio       VARCHAR(8)    NOT NULL,
        HoraFin          VARCHAR(8)    NOT NULL,
        Minutos          INT           NOT NULL,
        Motivo           VARCHAR(500)  NULL,
        status           CHAR(1)       NOT NULL CONSTRAINT DF_CA_Sobretiempo_St DEFAULT ('P'),
        Comments         VARCHAR(255)  NULL,
        NombreSustento   VARCHAR(255)  NULL,
        registerdate     DATETIME      NULL,
        ApprovalUser     VARCHAR(20)   NULL,
        ApprovalDate     DATETIME      NULL,
        xlastuser        VARCHAR(20)   NULL,
        xlastdate        VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_SobretiempoSolicitud PRIMARY KEY (Company, Person, Line)
    );
    CREATE INDEX IX_CA_Sobretiempo_Status
        ON dbo.CA_SobretiempoSolicitud (Company, status, registerdate DESC);
END
GO

/* Solicitud de goce compensatorio */
IF OBJECT_ID('dbo.CA_GoceCompensacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_GoceCompensacion (
        Company          VARCHAR(4)    NOT NULL,
        Person           VARCHAR(20)   NOT NULL,
        Line             INT           NOT NULL,
        Fecha            DATE          NOT NULL,
        HoraInicio       VARCHAR(8)    NOT NULL,
        HoraFin          VARCHAR(8)    NOT NULL,
        Minutos          INT           NOT NULL,
        Motivo           VARCHAR(500)  NULL,
        status           CHAR(1)       NOT NULL CONSTRAINT DF_CA_GoceComp_St DEFAULT ('P'),
        Comments         VARCHAR(255)  NULL,
        registerdate     DATETIME      NULL,
        ApprovalUser     VARCHAR(20)   NULL,
        ApprovalDate     DATETIME      NULL,
        xlastuser        VARCHAR(20)   NULL,
        xlastdate        VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_GoceCompensacion PRIMARY KEY (Company, Person, Line)
    );
    CREATE INDEX IX_CA_GoceComp_Status
        ON dbo.CA_GoceCompensacion (Company, status, registerdate DESC);
END
GO

/* Libro de banco de horas (solo efectivos) */
IF OBJECT_ID('dbo.CA_BancoHorasMov', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_BancoHorasMov (
        Company          VARCHAR(4)    NOT NULL,
        Person           VARCHAR(20)   NOT NULL,
        Line             INT           NOT NULL,
        TipoMov          VARCHAR(10)   NOT NULL,  -- CREDITO / DEBITO / DEUDA
        Origen           VARCHAR(30)   NOT NULL,  -- SOBRETIEMPO / GOCE / TARDANZA / PAPELETA_PERSONAL
        FechaEvento      DATE          NOT NULL,
        Minutos          INT           NOT NULL,  -- siempre positivo; el signo lo da TipoMov
        RefTipo          VARCHAR(20)   NULL,     -- SOBRETIEMPO / GOCE_COMP
        RefLine          INT           NULL,
        Motivo           VARCHAR(500)  NULL,
        registerdate     DATETIME      NOT NULL CONSTRAINT DF_CA_BancoHorasMov_Reg DEFAULT (GETDATE()),
        xlastuser        VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_BancoHorasMov PRIMARY KEY (Company, Person, Line)
    );
    CREATE INDEX IX_CA_BancoHorasMov_Person
        ON dbo.CA_BancoHorasMov (Company, Person, FechaEvento DESC);
    CREATE UNIQUE INDEX UX_CA_BancoHorasMov_Ref
        ON dbo.CA_BancoHorasMov (Company, Person, RefTipo, RefLine)
        WHERE RefTipo IS NOT NULL AND RefLine IS NOT NULL;
END
GO

/* Bandeja unificada: sobretiempo + goce */
CREATE OR ALTER PROCEDURE [dbo].[sp_ca_aprobar_compensaciones_web]
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

    SELECT *
    FROM (
        SELECT
            'SOBRETIEMPO' AS TipoSolicitud,
            SY_Person.Person,
            SY_Person.Name,
            s.Line AS id,
            s.Fecha,
            s.HoraInicio,
            s.HoraFin,
            s.Minutos,
            s.Motivo,
            s.status,
            s.ApprovalDate,
            s.Comments,
            s.NombreSustento,
            s.registerdate,
            flujo.nivel_actual,
            flujo.total_niveles,
            flujo.estado_flujo,
            flujo.descripcion_nivel
        FROM dbo.CA_SobretiempoSolicitud s
        INNER JOIN SY_Person
            ON s.Person = SY_Person.Person
           AND s.Company = @cia
        OUTER APPLY (
            SELECT
                nivel_actual = (
                    SELECT MIN(x.Nivel) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = s.Company AND x.Person = s.Person
                      AND x.TipoSolicitud = 'SOBRETIEMPO' AND x.Line = s.Line AND x.Estado = 'P'
                ),
                total_niveles = (
                    SELECT COUNT(*) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = s.Company AND x.Person = s.Person
                      AND x.TipoSolicitud = 'SOBRETIEMPO' AND x.Line = s.Line
                ),
                estado_flujo = (
                    SELECT TOP 1 CASE
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = s.Company AND y.Person = s.Person
                              AND y.TipoSolicitud = 'SOBRETIEMPO' AND y.Line = s.Line AND y.Estado = 'R'
                        ) THEN 'RECHAZADO'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = s.Company AND y.Person = s.Person
                              AND y.TipoSolicitud = 'SOBRETIEMPO' AND y.Line = s.Line AND y.Estado = 'P'
                        ) AND EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = s.Company AND y.Person = s.Person
                              AND y.TipoSolicitud = 'SOBRETIEMPO' AND y.Line = s.Line
                        ) THEN 'APROBADO'
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = s.Company AND y.Person = s.Person
                              AND y.TipoSolicitud = 'SOBRETIEMPO' AND y.Line = s.Line AND y.Estado = 'P'
                        ) THEN 'EN_APROBACION'
                        ELSE NULL
                    END
                ),
                descripcion_nivel = (
                    SELECT TOP 1 x.Descripcion FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = s.Company AND x.Person = s.Person
                      AND x.TipoSolicitud = 'SOBRETIEMPO' AND x.Line = s.Line AND x.Estado = 'P'
                    ORDER BY x.Nivel
                )
        ) flujo
        WHERE (@person = '0' OR s.Person = @person)
          AND (
                @dni = ''
                OR SY_Person.Person LIKE '%' + @dni + '%'
                OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
              )

        UNION ALL

        SELECT
            'GOCE_COMP' AS TipoSolicitud,
            SY_Person.Person,
            SY_Person.Name,
            g.Line AS id,
            g.Fecha,
            g.HoraInicio,
            g.HoraFin,
            g.Minutos,
            g.Motivo,
            g.status,
            g.ApprovalDate,
            g.Comments,
            CAST(NULL AS VARCHAR(255)) AS NombreSustento,
            g.registerdate,
            flujo.nivel_actual,
            flujo.total_niveles,
            flujo.estado_flujo,
            flujo.descripcion_nivel
        FROM dbo.CA_GoceCompensacion g
        INNER JOIN SY_Person
            ON g.Person = SY_Person.Person
           AND g.Company = @cia
        OUTER APPLY (
            SELECT
                nivel_actual = (
                    SELECT MIN(x.Nivel) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = g.Company AND x.Person = g.Person
                      AND x.TipoSolicitud = 'GOCE_COMP' AND x.Line = g.Line AND x.Estado = 'P'
                ),
                total_niveles = (
                    SELECT COUNT(*) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = g.Company AND x.Person = g.Person
                      AND x.TipoSolicitud = 'GOCE_COMP' AND x.Line = g.Line
                ),
                estado_flujo = (
                    SELECT TOP 1 CASE
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = g.Company AND y.Person = g.Person
                              AND y.TipoSolicitud = 'GOCE_COMP' AND y.Line = g.Line AND y.Estado = 'R'
                        ) THEN 'RECHAZADO'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = g.Company AND y.Person = g.Person
                              AND y.TipoSolicitud = 'GOCE_COMP' AND y.Line = g.Line AND y.Estado = 'P'
                        ) AND EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = g.Company AND y.Person = g.Person
                              AND y.TipoSolicitud = 'GOCE_COMP' AND y.Line = g.Line
                        ) THEN 'APROBADO'
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = g.Company AND y.Person = g.Person
                              AND y.TipoSolicitud = 'GOCE_COMP' AND y.Line = g.Line AND y.Estado = 'P'
                        ) THEN 'EN_APROBACION'
                        ELSE NULL
                    END
                ),
                descripcion_nivel = (
                    SELECT TOP 1 x.Descripcion FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = g.Company AND x.Person = g.Person
                      AND x.TipoSolicitud = 'GOCE_COMP' AND x.Line = g.Line AND x.Estado = 'P'
                    ORDER BY x.Nivel
                )
        ) flujo
        WHERE (@person = '0' OR g.Person = @person)
          AND (
                @dni = ''
                OR SY_Person.Person LIKE '%' + @dni + '%'
                OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
              )
    ) u
    ORDER BY u.Name, u.registerdate DESC;
END
GO
