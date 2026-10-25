/*
  Ficha de Datos (Portal Trabajador):
  - CA_FichaContactoSolicitud  (WF FICHA_CONTACTO)
  - CA_FichaEducacionSolicitud (WF FICHA_EDUCACION)
  Al aprobar nivel final se aplican cambios a SY_Person vía SPs de Planillas.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.WF_FlujoConfig
    WHERE Company = '' AND TipoSolicitud = 'FICHA_CONTACTO' AND Orden = 1
)
BEGIN
    INSERT INTO dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden, TipoAprobador, ProfileCode, Descripcion, Activo)
    VALUES
        ('', 'FICHA_CONTACTO', 1, 'JEFE_CC_CADENA', NULL,        'Jefe(s) por Centro de Costo / Organigrama', 1),
        ('', 'FICHA_CONTACTO', 2, 'ROL_PERFIL',     'APROBADOR', 'Gestión de RR.HH. / Personal', 1);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.WF_FlujoConfig
    WHERE Company = '' AND TipoSolicitud = 'FICHA_EDUCACION' AND Orden = 1
)
BEGIN
    INSERT INTO dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden, TipoAprobador, ProfileCode, Descripcion, Activo)
    VALUES
        ('', 'FICHA_EDUCACION', 1, 'JEFE_CC_CADENA', NULL,        'Jefe(s) por Centro de Costo / Organigrama', 1),
        ('', 'FICHA_EDUCACION', 2, 'ROL_PERFIL',     'APROBADOR', 'Gestión de RR.HH. / Personal', 1);
END
GO

IF OBJECT_ID('dbo.CA_FichaContactoSolicitud', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_FichaContactoSolicitud (
        Company          VARCHAR(4)    NOT NULL,
        Person           VARCHAR(20)   NOT NULL,
        Line             INT           NOT NULL,
        SecTelephone     VARCHAR(15)   NULL,
        Email            VARCHAR(255)  NULL,
        Address          VARCHAR(255)  NULL,
        Localite         VARCHAR(20)   NULL,
        Motivo           VARCHAR(500)  NULL,
        status           CHAR(1)       NOT NULL CONSTRAINT DF_CA_FichaContacto_St DEFAULT ('P'),
        Comments         VARCHAR(255)  NULL,
        registerdate     DATETIME      NULL,
        ApprovalUser     VARCHAR(20)   NULL,
        ApprovalDate     DATETIME      NULL,
        xlastuser        VARCHAR(20)   NULL,
        xlastdate        VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_FichaContactoSolicitud PRIMARY KEY (Company, Person, Line)
    );
END
GO

IF OBJECT_ID('dbo.CA_FichaEducacionSolicitud', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_FichaEducacionSolicitud (
        Company                        VARCHAR(4)    NOT NULL,
        Person                         VARCHAR(20)   NOT NULL,
        Line                           INT           NOT NULL,
        InstructionLevel               VARCHAR(20)   NULL,
        CostCenter1                    VARCHAR(20)   NULL,  -- institución PDT
        CostCenter2                    VARCHAR(20)   NULL,  -- carrera PDT
        AnioEgreso                     VARCHAR(10)   NULL,
        Specialty                      VARCHAR(100)  NULL,
        ProfesionalStudiesCenterType   CHAR(1)       NULL,
        IsTrainer                      CHAR(1)       NULL,
        Indicator                      CHAR(1)       NULL,
        Motivo                         VARCHAR(500)  NULL,
        status                         CHAR(1)       NOT NULL CONSTRAINT DF_CA_FichaEducacion_St DEFAULT ('P'),
        Comments                       VARCHAR(255)  NULL,
        registerdate                   DATETIME      NULL,
        ApprovalUser                   VARCHAR(20)   NULL,
        ApprovalDate                   DATETIME      NULL,
        xlastuser                      VARCHAR(20)   NULL,
        xlastdate                      VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_FichaEducacionSolicitud PRIMARY KEY (Company, Person, Line)
    );
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_ca_aprobar_ficha_datos_web]
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
            'FICHA_CONTACTO' AS TipoSolicitud,
            SY_Person.Person,
            SY_Person.Name,
            c.Line AS id,
            CAST(NULL AS VARCHAR(7)) AS Periodo,
            LEFT(
                'Tel: ' + ISNULL(c.SecTelephone, '-') +
                ' | Email: ' + ISNULL(c.Email, '-') +
                ' | Dir: ' + ISNULL(c.Address, '-'),
                300
            ) AS Detalle,
            c.Motivo,
            c.status,
            c.ApprovalDate,
            c.registerdate,
            flujo.nivel_actual,
            flujo.total_niveles,
            flujo.estado_flujo,
            flujo.descripcion_nivel
        FROM dbo.CA_FichaContactoSolicitud c
        INNER JOIN SY_Person ON c.Person = SY_Person.Person AND c.Company = @cia
        OUTER APPLY (
            SELECT
                nivel_actual = (
                    SELECT MIN(x.Nivel) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = c.Company AND x.Person = c.Person
                      AND x.TipoSolicitud = 'FICHA_CONTACTO' AND x.Line = c.Line AND x.Estado = 'P'
                ),
                total_niveles = (
                    SELECT COUNT(*) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = c.Company AND x.Person = c.Person
                      AND x.TipoSolicitud = 'FICHA_CONTACTO' AND x.Line = c.Line
                ),
                estado_flujo = (
                    SELECT TOP 1 CASE
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = c.Company AND y.Person = c.Person
                              AND y.TipoSolicitud = 'FICHA_CONTACTO' AND y.Line = c.Line AND y.Estado = 'R'
                        ) THEN 'RECHAZADO'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = c.Company AND y.Person = c.Person
                              AND y.TipoSolicitud = 'FICHA_CONTACTO' AND y.Line = c.Line AND y.Estado = 'P'
                        ) AND EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = c.Company AND y.Person = c.Person
                              AND y.TipoSolicitud = 'FICHA_CONTACTO' AND y.Line = c.Line
                        ) THEN 'APROBADO'
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = c.Company AND y.Person = c.Person
                              AND y.TipoSolicitud = 'FICHA_CONTACTO' AND y.Line = c.Line AND y.Estado = 'P'
                        ) THEN 'EN_APROBACION'
                        ELSE NULL
                    END
                ),
                descripcion_nivel = (
                    SELECT TOP 1 x.Descripcion FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = c.Company AND x.Person = c.Person
                      AND x.TipoSolicitud = 'FICHA_CONTACTO' AND x.Line = c.Line AND x.Estado = 'P'
                    ORDER BY x.Nivel
                )
        ) flujo
        WHERE (@person = '0' OR c.Person = @person)
          AND (
                @dni = ''
                OR SY_Person.Person LIKE '%' + @dni + '%'
                OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
              )

        UNION ALL

        SELECT
            'FICHA_EDUCACION' AS TipoSolicitud,
            SY_Person.Person,
            SY_Person.Name,
            e.Line AS id,
            CAST(NULL AS VARCHAR(7)) AS Periodo,
            LEFT(
                'Nivel: ' + ISNULL(e.InstructionLevel, '-') +
                ' | Inst: ' + ISNULL(e.CostCenter1, '-') +
                ' | Carrera: ' + ISNULL(e.CostCenter2, '-') +
                ' | Año: ' + ISNULL(e.AnioEgreso, '-'),
                300
            ) AS Detalle,
            e.Motivo,
            e.status,
            e.ApprovalDate,
            e.registerdate,
            flujo.nivel_actual,
            flujo.total_niveles,
            flujo.estado_flujo,
            flujo.descripcion_nivel
        FROM dbo.CA_FichaEducacionSolicitud e
        INNER JOIN SY_Person ON e.Person = SY_Person.Person AND e.Company = @cia
        OUTER APPLY (
            SELECT
                nivel_actual = (
                    SELECT MIN(x.Nivel) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = e.Company AND x.Person = e.Person
                      AND x.TipoSolicitud = 'FICHA_EDUCACION' AND x.Line = e.Line AND x.Estado = 'P'
                ),
                total_niveles = (
                    SELECT COUNT(*) FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = e.Company AND x.Person = e.Person
                      AND x.TipoSolicitud = 'FICHA_EDUCACION' AND x.Line = e.Line
                ),
                estado_flujo = (
                    SELECT TOP 1 CASE
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = e.Company AND y.Person = e.Person
                              AND y.TipoSolicitud = 'FICHA_EDUCACION' AND y.Line = e.Line AND y.Estado = 'R'
                        ) THEN 'RECHAZADO'
                        WHEN NOT EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = e.Company AND y.Person = e.Person
                              AND y.TipoSolicitud = 'FICHA_EDUCACION' AND y.Line = e.Line AND y.Estado = 'P'
                        ) AND EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = e.Company AND y.Person = e.Person
                              AND y.TipoSolicitud = 'FICHA_EDUCACION' AND y.Line = e.Line
                        ) THEN 'APROBADO'
                        WHEN EXISTS (
                            SELECT 1 FROM dbo.WF_SolicitudPaso y
                            WHERE y.Company = e.Company AND y.Person = e.Person
                              AND y.TipoSolicitud = 'FICHA_EDUCACION' AND y.Line = e.Line AND y.Estado = 'P'
                        ) THEN 'EN_APROBACION'
                        ELSE NULL
                    END
                ),
                descripcion_nivel = (
                    SELECT TOP 1 x.Descripcion FROM dbo.WF_SolicitudPaso x
                    WHERE x.Company = e.Company AND x.Person = e.Person
                      AND x.TipoSolicitud = 'FICHA_EDUCACION' AND x.Line = e.Line AND x.Estado = 'P'
                    ORDER BY x.Nivel
                )
        ) flujo
        WHERE (@person = '0' OR e.Person = @person)
          AND (
                @dni = ''
                OR SY_Person.Person LIKE '%' + @dni + '%'
                OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
              )
    ) u
    ORDER BY u.Name, u.registerdate DESC;
END
GO
