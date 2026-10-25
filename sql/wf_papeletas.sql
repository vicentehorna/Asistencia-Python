/*
  1) Generaliza WF_SolicitudPaso con TipoSolicitud (VACACIONES / PAPELETA / ...).
  2) Catálogo y solicitudes de papeletas (demo PromPerú).
  3) Config de flujo PAPELETA: Jefe CC -> APROBADOR.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* --- WF: agregar TipoSolicitud --- */
IF COL_LENGTH('dbo.WF_SolicitudPaso', 'TipoSolicitud') IS NULL
BEGIN
    ALTER TABLE dbo.WF_SolicitudPaso
        ADD TipoSolicitud VARCHAR(20) NOT NULL
            CONSTRAINT DF_WF_SolicitudPaso_Tipo DEFAULT ('VACACIONES');
END
GO

IF EXISTS (
    SELECT 1 FROM sys.key_constraints
    WHERE name = 'UQ_WF_SolicitudPaso' AND parent_object_id = OBJECT_ID('dbo.WF_SolicitudPaso')
)
    ALTER TABLE dbo.WF_SolicitudPaso DROP CONSTRAINT UQ_WF_SolicitudPaso;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'UQ_WF_SolicitudPaso_Tipo' AND object_id = OBJECT_ID('dbo.WF_SolicitudPaso')
)
BEGIN
    CREATE UNIQUE INDEX UQ_WF_SolicitudPaso_Tipo
        ON dbo.WF_SolicitudPaso (Company, Person, TipoSolicitud, Line, Nivel);
END
GO

UPDATE dbo.WF_SolicitudPaso
SET TipoSolicitud = 'VACACIONES'
WHERE NULLIF(LTRIM(RTRIM(TipoSolicitud)), '') IS NULL
   OR TipoSolicitud = '';
GO

/* Config PAPELETA (mismo 2 niveles que vacaciones) */
IF NOT EXISTS (
    SELECT 1 FROM dbo.WF_FlujoConfig
    WHERE Company = '' AND TipoSolicitud = 'PAPELETA' AND Orden = 1
)
BEGIN
    INSERT INTO dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden, TipoAprobador, ProfileCode, Descripcion, Activo)
    VALUES
        ('', 'PAPELETA', 1, 'JEFE_CC_CADENA', NULL,        'Jefe(s) por Centro de Costo / Organigrama', 1),
        ('', 'PAPELETA', 2, 'ROL_PERFIL',     'APROBADOR', 'Gestión de RR.HH. / Personal', 1);
END
GO

/* --- Catálogo tipos de papeleta --- */
IF OBJECT_ID('dbo.CA_PapeletaTipo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_PapeletaTipo (
        Codigo            VARCHAR(30)  NOT NULL PRIMARY KEY,
        Nombre            VARCHAR(120) NOT NULL,
        ModoDefault       CHAR(1)      NOT NULL CONSTRAINT DF_CA_PapeletaTipo_Modo DEFAULT ('H'), -- H=horas D=días
        RequiereSustento  BIT          NOT NULL CONSTRAINT DF_CA_PapeletaTipo_Sust DEFAULT (0),
        SortOrder         INT          NOT NULL CONSTRAINT DF_CA_PapeletaTipo_Ord DEFAULT (100),
        Activo            BIT          NOT NULL CONSTRAINT DF_CA_PapeletaTipo_Act DEFAULT (1)
    );
END
GO

MERGE dbo.CA_PapeletaTipo AS t
USING (VALUES
    ('COMISION',         'Comisión de Servicios (Oficial)', 'H', 0, 10),
    ('PERSONAL',         'Asuntos Personales',              'H', 0, 20),
    ('MEDICA',           'Atención Médica (Essalud/EPS)',   'H', 1, 30),
    ('DESCANSO_CORTO',   'Descanso Médico Corto (1-2 días)','D', 1, 40),
    ('LUTO_PATERNIDAD',  'Licencia por Luto / Paternidad',  'D', 1, 50)
) AS s (Codigo, Nombre, ModoDefault, RequiereSustento, SortOrder)
ON t.Codigo = s.Codigo
WHEN MATCHED THEN
    UPDATE SET
        Nombre = s.Nombre,
        ModoDefault = s.ModoDefault,
        RequiereSustento = s.RequiereSustento,
        SortOrder = s.SortOrder,
        Activo = 1
WHEN NOT MATCHED THEN
    INSERT (Codigo, Nombre, ModoDefault, RequiereSustento, SortOrder, Activo)
    VALUES (s.Codigo, s.Nombre, s.ModoDefault, s.RequiereSustento, s.SortOrder, 1);
GO

/* --- Solicitudes de papeleta --- */
IF OBJECT_ID('dbo.CA_PapeletaSolicitud', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_PapeletaSolicitud (
        Company          VARCHAR(4)   NOT NULL,
        Person           VARCHAR(20)  NOT NULL,
        Line             INT          NOT NULL,
        TipoCodigo       VARCHAR(30)  NOT NULL,
        Modo             CHAR(1)      NOT NULL, -- H / D
        Fecha            DATE         NULL,    -- modo H
        HoraInicio       VARCHAR(8)   NULL,    -- HH:mm
        HoraFin          VARCHAR(8)   NULL,
        Horas            DECIMAL(6,2) NULL,
        FechaInicio      DATE         NULL,    -- modo D
        FechaFin         DATE         NULL,
        Dias             INT          NULL,
        Motivo           VARCHAR(500) NULL,
        status           CHAR(1)      NOT NULL CONSTRAINT DF_CA_PapeletaSolicitud_St DEFAULT ('P'),
        Comments         VARCHAR(255) NULL,    -- SUSTENTO_DRIVE:...
        NombreSustento   VARCHAR(255) NULL,
        registerdate     DATETIME     NULL,
        ApprovalUser     VARCHAR(20)  NULL,
        ApprovalDate     DATETIME     NULL,
        xlastuser        VARCHAR(20)  NULL,
        xlastdate        VARCHAR(20)  NULL,
        CONSTRAINT PK_CA_PapeletaSolicitud PRIMARY KEY (Company, Person, Line),
        CONSTRAINT FK_CA_PapeletaSolicitud_Tipo
            FOREIGN KEY (TipoCodigo) REFERENCES dbo.CA_PapeletaTipo (Codigo)
    );
    CREATE INDEX IX_CA_PapeletaSolicitud_Status
        ON dbo.CA_PapeletaSolicitud (Company, status, registerdate DESC);
END
GO

/* Listado bandeja papeletas */
CREATE OR ALTER PROCEDURE [dbo].[sp_ca_aprobarpapeletas_web]
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
        p.Line AS id,
        p.TipoCodigo,
        t.Nombre AS TipoNombre,
        p.Modo,
        p.Fecha,
        p.HoraInicio,
        p.HoraFin,
        p.Horas,
        p.FechaInicio,
        p.FechaFin,
        p.Dias,
        p.Motivo,
        p.status,
        p.ApprovalDate,
        p.Comments,
        p.NombreSustento,
        flujo.nivel_actual,
        flujo.total_niveles,
        flujo.estado_flujo,
        flujo.descripcion_nivel,
        flujo.tipo_aprobador_actual,
        flujo.aprobador_person_actual,
        flujo.profile_code_actual
    FROM dbo.CA_PapeletaSolicitud p
    INNER JOIN SY_Person
        ON p.Person = SY_Person.Person
       AND p.Company = @cia
    LEFT JOIN dbo.CA_PapeletaTipo t ON t.Codigo = p.TipoCodigo
    OUTER APPLY (
        SELECT
            nivel_actual = (
                SELECT MIN(x.Nivel)
                FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = p.Company AND x.Person = p.Person
                  AND x.TipoSolicitud = 'PAPELETA' AND x.Line = p.Line AND x.Estado = 'P'
            ),
            total_niveles = (
                SELECT COUNT(*)
                FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = p.Company AND x.Person = p.Person
                  AND x.TipoSolicitud = 'PAPELETA' AND x.Line = p.Line
            ),
            estado_flujo = (
                SELECT TOP 1
                    CASE
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = p.Company AND y.Person = p.Person
                              AND y.TipoSolicitud = 'PAPELETA' AND y.Line = p.Line AND y.Estado = 'R'
                        ) THEN 'RECHAZADO'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = p.Company AND y.Person = p.Person
                              AND y.TipoSolicitud = 'PAPELETA' AND y.Line = p.Line AND y.Estado = 'P'
                        ) AND EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = p.Company AND y.Person = p.Person
                              AND y.TipoSolicitud = 'PAPELETA' AND y.Line = p.Line
                        ) THEN 'APROBADO'
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = p.Company AND y.Person = p.Person
                              AND y.TipoSolicitud = 'PAPELETA' AND y.Line = p.Line AND y.Estado = 'P'
                        ) THEN 'EN_APROBACION'
                        ELSE NULL
                    END
            ),
            descripcion_nivel = (
                SELECT TOP 1 x.Descripcion
                FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = p.Company AND x.Person = p.Person
                  AND x.TipoSolicitud = 'PAPELETA' AND x.Line = p.Line AND x.Estado = 'P'
                ORDER BY x.Nivel
            ),
            tipo_aprobador_actual = (
                SELECT TOP 1 x.TipoAprobador
                FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = p.Company AND x.Person = p.Person
                  AND x.TipoSolicitud = 'PAPELETA' AND x.Line = p.Line AND x.Estado = 'P'
                ORDER BY x.Nivel
            ),
            aprobador_person_actual = (
                SELECT TOP 1 x.AprobadorPerson
                FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = p.Company AND x.Person = p.Person
                  AND x.TipoSolicitud = 'PAPELETA' AND x.Line = p.Line AND x.Estado = 'P'
                ORDER BY x.Nivel
            ),
            profile_code_actual = (
                SELECT TOP 1 x.ProfileCode
                FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = p.Company AND x.Person = p.Person
                  AND x.TipoSolicitud = 'PAPELETA' AND x.Line = p.Line AND x.Estado = 'P'
                ORDER BY x.Nivel
            )
    ) flujo
    WHERE (@person = '0' OR p.Person = @person)
      AND (
            @dni = ''
            OR SY_Person.Person LIKE '%' + @dni + '%'
            OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
          )
    ORDER BY 2, p.registerdate DESC;
END
GO
