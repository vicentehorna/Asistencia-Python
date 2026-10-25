/*
  Teletrabajo (Ley 31572):
  - CA_TeletrabajoAcuerdo     modalidad TOTAL/PARCIAL
  - CA_TeletrabajoRolSolicitud solicitud de rol mensual (WF TELETRABAJO)
  - CA_TeletrabajoDia          calendario efectivo aprobado
  - CA_TeletrabajoMatriz       actividades / entregables SERVIR
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.WF_FlujoConfig
    WHERE Company = '' AND TipoSolicitud = 'TELETRABAJO' AND Orden = 1
)
BEGIN
    INSERT INTO dbo.WF_FlujoConfig (Company, TipoSolicitud, Orden, TipoAprobador, ProfileCode, Descripcion, Activo)
    VALUES
        ('', 'TELETRABAJO', 1, 'JEFE_CC_CADENA', NULL,        'Jefe(s) por Centro de Costo / Organigrama', 1),
        ('', 'TELETRABAJO', 2, 'ROL_PERFIL',     'APROBADOR', 'Gestión de RR.HH. / Personal', 1);
END
GO

IF OBJECT_ID('dbo.CA_TeletrabajoAcuerdo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_TeletrabajoAcuerdo (
        Company          VARCHAR(4)    NOT NULL,
        Person           VARCHAR(20)   NOT NULL,
        Modalidad        VARCHAR(10)   NOT NULL,  -- TOTAL / PARCIAL
        FechaInicio      DATE          NULL,
        FechaFin         DATE          NULL,
        LugarDeclarado   VARCHAR(255)  NULL,
        Activo           BIT           NOT NULL CONSTRAINT DF_CA_TTAcuerdo_Act DEFAULT (1),
        xlastuser        VARCHAR(20)   NULL,
        xlastdate        VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_TeletrabajoAcuerdo PRIMARY KEY (Company, Person)
    );
END
GO

IF OBJECT_ID('dbo.CA_TeletrabajoRolSolicitud', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_TeletrabajoRolSolicitud (
        Company          VARCHAR(4)    NOT NULL,
        Person           VARCHAR(20)   NOT NULL,
        Line             INT           NOT NULL,
        Periodo          VARCHAR(7)    NOT NULL,  -- YYYY-MM
        DiasRemotos      VARCHAR(50)   NOT NULL,  -- '1,3,5' = Lun,Mié,Vie (1=Lun..7=Dom)
        Motivo           VARCHAR(500)  NULL,
        status           CHAR(1)       NOT NULL CONSTRAINT DF_CA_TTRol_St DEFAULT ('P'),
        Comments         VARCHAR(255)  NULL,
        registerdate     DATETIME      NULL,
        ApprovalUser     VARCHAR(20)   NULL,
        ApprovalDate     DATETIME      NULL,
        xlastuser        VARCHAR(20)   NULL,
        xlastdate        VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_TeletrabajoRolSolicitud PRIMARY KEY (Company, Person, Line)
    );
    CREATE INDEX IX_CA_TTRol_Periodo
        ON dbo.CA_TeletrabajoRolSolicitud (Company, Person, Periodo, status);
END
GO

IF OBJECT_ID('dbo.CA_TeletrabajoDia', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_TeletrabajoDia (
        Company          VARCHAR(4)    NOT NULL,
        Person           VARCHAR(20)   NOT NULL,
        Fecha            DATE          NOT NULL,
        ModalidadDia     CHAR(1)       NOT NULL,  -- P=Presencial R=Remoto
        Lugar            VARCHAR(255)  NULL,
        RefLine          INT           NULL,      -- Line de CA_TeletrabajoRolSolicitud
        registerdate     DATETIME      NOT NULL CONSTRAINT DF_CA_TTDia_Reg DEFAULT (GETDATE()),
        xlastuser        VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_TeletrabajoDia PRIMARY KEY (Company, Person, Fecha)
    );
    CREATE INDEX IX_CA_TTDia_Periodo
        ON dbo.CA_TeletrabajoDia (Company, Person, Fecha);
END
GO

IF OBJECT_ID('dbo.CA_TeletrabajoMatriz', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CA_TeletrabajoMatriz (
        Company            VARCHAR(4)    NOT NULL,
        Person             VARCHAR(20)   NOT NULL,
        Line               INT           NOT NULL,
        Periodo            VARCHAR(7)    NOT NULL,
        Actividad          VARCHAR(500)  NOT NULL,
        Entregable         VARCHAR(300)  NOT NULL,
        FechaLimite        DATE          NOT NULL,
        PorcentajeAvance   DECIMAL(5,2)  NOT NULL CONSTRAINT DF_CA_TTMatriz_Pct DEFAULT (0),
        EstadoEval         VARCHAR(20)   NOT NULL CONSTRAINT DF_CA_TTMatriz_Est DEFAULT ('EN_PROCESO'),
        ComentarioJefe     VARCHAR(500)  NULL,
        Comments           VARCHAR(255)  NULL,  -- SUSTENTO_LOCAL:... / SUSTENTO_DRIVE:...
        NombreSustento     VARCHAR(255)  NULL,
        registerdate       DATETIME      NULL,
        xlastuser          VARCHAR(20)   NULL,
        xlastdate          VARCHAR(20)   NULL,
        CONSTRAINT PK_CA_TeletrabajoMatriz PRIMARY KEY (Company, Person, Line)
    );
    CREATE INDEX IX_CA_TTMatriz_Periodo
        ON dbo.CA_TeletrabajoMatriz (Company, Person, Periodo);
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_ca_aprobar_teletrabajo_web]
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
        s.Line AS id,
        s.Periodo,
        s.DiasRemotos,
        s.Motivo,
        s.status,
        s.ApprovalDate,
        s.registerdate,
        flujo.nivel_actual,
        flujo.total_niveles,
        flujo.estado_flujo,
        flujo.descripcion_nivel
    FROM dbo.CA_TeletrabajoRolSolicitud s
    INNER JOIN SY_Person
        ON s.Person = SY_Person.Person
       AND s.Company = @cia
    OUTER APPLY (
        SELECT
            nivel_actual = (
                SELECT MIN(x.Nivel) FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = s.Company AND x.Person = s.Person
                  AND x.TipoSolicitud = 'TELETRABAJO' AND x.Line = s.Line AND x.Estado = 'P'
            ),
            total_niveles = (
                SELECT COUNT(*) FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = s.Company AND x.Person = s.Person
                  AND x.TipoSolicitud = 'TELETRABAJO' AND x.Line = s.Line
            ),
            estado_flujo = (
                SELECT TOP 1 CASE
                    WHEN EXISTS (
                        SELECT 1 FROM dbo.WF_SolicitudPaso y
                        WHERE y.Company = s.Company AND y.Person = s.Person
                          AND y.TipoSolicitud = 'TELETRABAJO' AND y.Line = s.Line AND y.Estado = 'R'
                    ) THEN 'RECHAZADO'
                    WHEN NOT EXISTS (
                        SELECT 1 FROM dbo.WF_SolicitudPaso y
                        WHERE y.Company = s.Company AND y.Person = s.Person
                          AND y.TipoSolicitud = 'TELETRABAJO' AND y.Line = s.Line AND y.Estado = 'P'
                    ) AND EXISTS (
                        SELECT 1 FROM dbo.WF_SolicitudPaso y
                        WHERE y.Company = s.Company AND y.Person = s.Person
                          AND y.TipoSolicitud = 'TELETRABAJO' AND y.Line = s.Line
                    ) THEN 'APROBADO'
                    WHEN EXISTS (
                        SELECT 1 FROM dbo.WF_SolicitudPaso y
                        WHERE y.Company = s.Company AND y.Person = s.Person
                          AND y.TipoSolicitud = 'TELETRABAJO' AND y.Line = s.Line AND y.Estado = 'P'
                    ) THEN 'EN_APROBACION'
                    ELSE NULL
                END
            ),
            descripcion_nivel = (
                SELECT TOP 1 x.Descripcion FROM dbo.WF_SolicitudPaso x
                WHERE x.Company = s.Company AND x.Person = s.Person
                  AND x.TipoSolicitud = 'TELETRABAJO' AND x.Line = s.Line AND x.Estado = 'P'
                ORDER BY x.Nivel
            )
    ) flujo
    WHERE (@person = '0' OR s.Person = @person)
      AND (
            @dni = ''
            OR SY_Person.Person LIKE '%' + @dni + '%'
            OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
          )
    ORDER BY 2, s.registerdate DESC;
END
GO
