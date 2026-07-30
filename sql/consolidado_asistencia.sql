/*
  Consolidado SQL - Sistema de Asistencia
  Generado: 2026-07-08 15:33:13
  Total de scripts: 48
  Orden: tables, migrations, procedimientos/otros scripts.
*/
GO

/* ============================================================================
   01. sql/tables/CA_RegularizacionFalta.sql
   ============================================================================ */
/*

  Tabla: dbo.CA_RegularizacionFalta

  Uso: Auditoría de regularización de faltas (encargo de empresa) desde Consolidado de Asistencia.

       Por cada día regularizado se crean marcas de entrada/salida según horario.

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE TABLE [dbo].[CA_RegularizacionFalta] (

    [IdRegularizacion] INT IDENTITY(1, 1) NOT NULL,

    [company]          CHAR(4) NOT NULL,

    [Person]           VARCHAR(20) NOT NULL,

    [Fecha]            DATE NOT NULL,

    [IdHorario]        INT NULL,

    [HoraEntrada]      DATETIME NOT NULL,

    [HoraSalida]       DATETIME NOT NULL,

    [Comentario]       VARCHAR(255) NULL,

    [xlastuser]        VARCHAR(20) NULL,

    [xlastdate]        DATETIME NOT NULL,

    CONSTRAINT [PK_CA_RegularizacionFalta] PRIMARY KEY CLUSTERED ([IdRegularizacion] ASC)

) ON [PRIMARY];

GO



CREATE UNIQUE NONCLUSTERED INDEX [UX_CA_RegularizacionFalta_company_person_fecha]

    ON [dbo].[CA_RegularizacionFalta] ([company] ASC, [Person] ASC, [Fecha] ASC);

GO



ALTER TABLE [dbo].[CA_RegularizacionFalta]

    ADD CONSTRAINT [DF_CA_RegularizacionFalta_xlastdate]

    DEFAULT (GETDATE()) FOR [xlastdate];

GO

GO

/* ============================================================================
   02. sql/tables/RegistroAsistencia.sql
   ============================================================================ */
/*

  Tabla: dbo.RegistroAsistencia

  Uso: Gestión de Marcas (consulta vía sp_pr_listadomarcas_web, alta manual en api/marcas/manual)

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE TABLE [dbo].[RegistroAsistencia] (

    [IdRegistro]       INT IDENTITY(1, 1) NOT NULL,

    [IdTrabajador]     INT NOT NULL,

    [FechaHoraIngreso] DATETIME NOT NULL,

    [RutaFoto]         VARCHAR(255) NULL,

    [Person]           VARCHAR(20) NULL,

    [company]          CHAR(4) NULL,

    [xlastuser]        VARCHAR(20) NULL,

    [xlastdate]        DATETIME NULL,

    [flagmanual]       CHAR(1) NOT NULL,

    [MotivoManual]     VARCHAR(255) NULL,

    [estado]           CHAR(1) NOT NULL,

    CONSTRAINT [PK_RegistroAsistencia] PRIMARY KEY CLUSTERED ([IdRegistro] ASC)

        WITH (

            PAD_INDEX = OFF,

            STATISTICS_NORECOMPUTE = OFF,

            IGNORE_DUP_KEY = OFF,

            ALLOW_ROW_LOCKS = ON,

            ALLOW_PAGE_LOCKS = ON

        ) ON [PRIMARY]

) ON [PRIMARY];

GO



ALTER TABLE [dbo].[RegistroAsistencia]

    ADD CONSTRAINT [DF_RegistroAsistencia_FechaHoraIngreso]

    DEFAULT (GETDATE()) FOR [FechaHoraIngreso];

GO



ALTER TABLE [dbo].[RegistroAsistencia]

    ADD CONSTRAINT [DF_RegistroAsistencia_flagmanual]

    DEFAULT ('N') FOR [flagmanual];

GO



ALTER TABLE [dbo].[RegistroAsistencia]

    ADD CONSTRAINT [DF_RegistroAsistencia_estado]

    DEFAULT ('A') FOR [estado];

GO



ALTER TABLE [dbo].[RegistroAsistencia] WITH CHECK

    ADD CONSTRAINT [FK_RegistroAsistencia_Trabajadores]

    FOREIGN KEY ([IdTrabajador])

    REFERENCES [dbo].[Trabajadores] ([IdTrabajador]);

GO

GO

/* ============================================================================
   03. sql/migrations/20260325_RegistroAsistencia_estado.sql
   ============================================================================ */
/*

  Migración: columna estado en RegistroAsistencia

  A = activo (visible en Gestión de Marcas), I = inactivo (oculto)

  Ejecutar una vez en bases existentes.

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



IF COL_LENGTH('dbo.RegistroAsistencia', 'estado') IS NULL

BEGIN

    ALTER TABLE [dbo].[RegistroAsistencia]

        ADD [estado] CHAR(1) NOT NULL

            CONSTRAINT [DF_RegistroAsistencia_estado] DEFAULT ('A') WITH VALUES;

END;

GO

GO

/* ============================================================================
   04. sql/migrations/20260625_CA_RegularizacionFalta.sql
   ============================================================================ */
/*

  Migración: tabla CA_RegularizacionFalta (regularización de faltas desde consolidado)

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



IF OBJECT_ID(N'dbo.CA_RegularizacionFalta', N'U') IS NULL

BEGIN

    CREATE TABLE [dbo].[CA_RegularizacionFalta] (

        [IdRegularizacion] INT IDENTITY(1, 1) NOT NULL,

        [company]          CHAR(4) NOT NULL,

        [Person]           VARCHAR(20) NOT NULL,

        [Fecha]            DATE NOT NULL,

        [IdHorario]        INT NULL,

        [HoraEntrada]      DATETIME NOT NULL,

        [HoraSalida]       DATETIME NOT NULL,

        [Comentario]       VARCHAR(255) NULL,

        [xlastuser]        VARCHAR(20) NULL,

        [xlastdate]        DATETIME NOT NULL,

        CONSTRAINT [PK_CA_RegularizacionFalta] PRIMARY KEY CLUSTERED ([IdRegularizacion] ASC)

    ) ON [PRIMARY];



    CREATE UNIQUE NONCLUSTERED INDEX [UX_CA_RegularizacionFalta_company_person_fecha]

        ON [dbo].[CA_RegularizacionFalta] ([company] ASC, [Person] ASC, [Fecha] ASC);



    ALTER TABLE [dbo].[CA_RegularizacionFalta]

        ADD CONSTRAINT [DF_CA_RegularizacionFalta_xlastdate]

        DEFAULT (GETDATE()) FOR [xlastdate];

END

GO

GO

/* ============================================================================
   05. sql/sp_ca_listajustificaciones_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_listajustificaciones_web

  Uso: Justificaciones por Persona (api/justificaciones_persona/listar)

  Parámetros: @cia, @person ('0' = todos los trabajadores)

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_listajustificaciones_web]

    @cia    CHAR(4),

    @person VARCHAR(20)

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        P.Person AS DNI,

        P.Name,

        TJ.Abreviatura,

        JP.FechaInicio,

        JP.FechaFin,

        JP.Comentario,

        JP.Id AS ID,

        JP.IdJustificacion AS idjustificacion

    FROM CA_JustificacionPersona JP

    INNER JOIN SY_Person P

        ON JP.Person = P.Person

    INNER JOIN CA_TipoJustificacion TJ

        ON JP.IdJustificacion = TJ.IdJustificacion

    WHERE JP.company = @cia

      AND (@person = '0' OR JP.Person = @person)

    ORDER BY

        P.Name,

        JP.FechaInicio;

END

GO

GO

/* ============================================================================
   06. sql/sp_ca_listarfaltasregularizar_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_listarfaltasregularizar_web

  Uso: Consolidado de Asistencia — modal Regularizar (días con falta del trabajador)

  Parámetros: @cia, @person, @fechaini, @fechafin

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_listarfaltasregularizar_web]

    @cia       CHAR(4),

    @person    VARCHAR(20),

    @fechaini  DATETIME,

    @fechafin  DATETIME

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        RA.Fecha,

        RA.DiaSem,

        ISNULL(RA.motivo, '') AS motivo,

        RA.IdHorario,

        H.NombreHorario,

        CASE DATEPART(WEEKDAY, RA.Fecha)

            WHEN 2 THEN CONVERT(VARCHAR(5), H.Lunes_Entrada, 108)

            WHEN 3 THEN CONVERT(VARCHAR(5), H.Martes_Entrada, 108)

            WHEN 4 THEN CONVERT(VARCHAR(5), H.Miercoles_Entrada, 108)

            WHEN 5 THEN CONVERT(VARCHAR(5), H.Jueves_Entrada, 108)

            WHEN 6 THEN CONVERT(VARCHAR(5), H.Viernes_Entrada, 108)

            WHEN 7 THEN CONVERT(VARCHAR(5), H.Sabado_Entrada, 108)

            ELSE CONVERT(VARCHAR(5), H.Domingo_Entrada, 108)

        END AS HoraEntrada,

        CASE DATEPART(WEEKDAY, RA.Fecha)

            WHEN 2 THEN CONVERT(VARCHAR(5), H.Lunes_Salida, 108)

            WHEN 3 THEN CONVERT(VARCHAR(5), H.Martes_Salida, 108)

            WHEN 4 THEN CONVERT(VARCHAR(5), H.Miercoles_Salida, 108)

            WHEN 5 THEN CONVERT(VARCHAR(5), H.Jueves_Salida, 108)

            WHEN 6 THEN CONVERT(VARCHAR(5), H.Viernes_Salida, 108)

            WHEN 7 THEN CONVERT(VARCHAR(5), H.Sabado_Salida, 108)

            ELSE CONVERT(VARCHAR(5), H.Domingo_Salida, 108)

        END AS HoraSalida

    FROM ResumenAsistencia RA

    INNER JOIN Horarios H

        ON RA.IdHorario = H.IdHorario

    WHERE RA.Company = @cia

      AND RA.Person = @person

      AND RA.Falta = 'Y'

      AND RA.Fecha BETWEEN CONVERT(DATE, @fechaini) AND CONVERT(DATE, @fechafin)

      AND NOT EXISTS (

          SELECT 1

          FROM CA_RegularizacionFalta RF

          WHERE RF.company = RA.Company

            AND RF.Person = RA.Person

            AND RF.Fecha = RA.Fecha

      )

    ORDER BY RA.Fecha;

END

GO

GO

/* ============================================================================
   07. sql/sp_ca_procesarasistencia_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_procesarasistencia_web

  Uso: Procesar Asistencia — botón Iniciar Proceso (api/asistencia/procesar_individual)

  Parámetros: @cia, @person, @fechaini, @fechafin



  Tablas: ResumenAsistencia, AsignacionHorarios, Horarios, SY_Holiday, RegistroAsistencia,

          PR_VacationDetail, PR_EmployeeMedicalRest, PR_MedicalRestType,

          CA_JustificacionPersona, CA_TipoJustificacion, SY_Person



  Sin marcas: vacaciones -> descanso médico (PDT 20) -> licencia con goce (PDT 26) -> justificación CA -> falta.

  RegistroAsistencia: solo marcas con estado = 'A' (activas). Las inactivas (I) se ignoran.

  Con 2 marcas: la 2.ª es salida. Con 3 marcas: si la 3.ª está más cerca de la salida

  teórica que del retorno de refrigerio, se toma como salida y E. refri queda vacía.

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_procesarasistencia_web]
    @cia       CHAR(4),
    @person    VARCHAR(20),
    @fechaini  DATETIME,
    @fechafin  DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FechaProceso DATETIME;
    DECLARE @idhorario INT;
    DECLARE @cant INT;
    DECLARE @tolerancia INT;
    DECLARE @dia INT;
    DECLARE @HingT TIME;
    DECLARE @HingR TIME;
    DECLARE @HsalidaT TIME;
    DECLARE @HEntradaRefriT TIME;
    DECLARE @SalidaTeorica DATETIME;
    DECLARE @MinutosAdicionales INT;
    DECLARE @Entrada DATETIME;
    DECLARE @SalidaRef DATETIME;
    DECLARE @RetornoRef DATETIME;
    DECLARE @Salida DATETIME;
    DECLARE @motivofalta VARCHAR(20);

    SET @FechaProceso = CONVERT(DATE, @fechaini);

    DELETE FROM ResumenAsistencia
    WHERE Person = @person
      AND Company = @cia
      AND Fecha BETWEEN CONVERT(DATE, @fechaini) AND CONVERT(DATE, @fechafin);

    WHILE @FechaProceso <= CONVERT(DATE, @fechafin)
    BEGIN
        SET @idhorario = NULL;
        SET @cant = 0;
        SET @tolerancia = 0;
        SET @dia = DATEPART(WEEKDAY, @FechaProceso);
        SET @HingT = NULL;
        SET @HingR = NULL;
        SET @HsalidaT = NULL;
        SET @HEntradaRefriT = NULL;
        SET @SalidaTeorica = NULL;
        SET @MinutosAdicionales = 0;
        SET @Entrada = NULL;
        SET @SalidaRef = NULL;
        SET @RetornoRef = NULL;
        SET @Salida = NULL;
        SET @motivofalta = NULL;

        IF NOT EXISTS (
            SELECT 1
            FROM AsignacionHorarios
            WHERE Person = @person
              AND Company = @cia
              AND @FechaProceso BETWEEN FechaInicio AND ISNULL(FechaFin, '99991231')
        )
        BEGIN
            SET @FechaProceso = DATEADD(DAY, 1, @FechaProceso);
            CONTINUE;
        END;

        SELECT TOP 1
            @idhorario = IdHorario
        FROM AsignacionHorarios
        WHERE Person = @person
          AND Company = @cia
          AND @FechaProceso BETWEEN FechaInicio AND ISNULL(FechaFin, '99991231')
        ORDER BY FechaInicio DESC,
                 IdAsignacion DESC;

        IF (
            SELECT CASE
                WHEN @dia = 2 THEN Lunes_Laborable
                WHEN @dia = 3 THEN Martes_Laborable
                WHEN @dia = 4 THEN Miercoles_Laborable
                WHEN @dia = 5 THEN Jueves_Laborable
                WHEN @dia = 6 THEN Viernes_Laborable
                WHEN @dia = 7 THEN Sabado_Laborable
                ELSE Domingo_Laborable
            END
            FROM Horarios
            WHERE IdHorario = @idhorario
        ) = 0
        BEGIN
            SET @FechaProceso = DATEADD(DAY, 1, @FechaProceso);
            CONTINUE;
        END;

        /* Feriado: aparece en resumen, no es falta (CA_Feriados o SY_Holiday). */
        IF EXISTS (
            SELECT 1
            FROM SY_Holiday
            WHERE CONVERT(DATE, HolidayDate) = CONVERT(DATE, @FechaProceso)
              AND Status = 'A'
        )
        OR EXISTS (
            SELECT 1
            FROM CA_Feriados
            WHERE CONVERT(DATE, Fecha) = CONVERT(DATE, @FechaProceso)
        )
        BEGIN
            INSERT INTO ResumenAsistencia (
                Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                MinutosTarde, MinutosAdicionales, Falta, XLastUser, XLastDate, DiaSem, motivo
            )
            VALUES (
                @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                0, 0, 'N', 'ADMIN', GETDATE(),
                CASE
                    WHEN @dia = 2 THEN 'LU' WHEN @dia = 3 THEN 'MA' WHEN @dia = 4 THEN 'MI'
                    WHEN @dia = 5 THEN 'JU' WHEN @dia = 6 THEN 'VI' WHEN @dia = 7 THEN 'SA'
                    ELSE 'DO'
                END,
                'Feriado'
            );

            UPDATE SY_Person
            SET FechaProcesamientoCA = GETDATE()
            WHERE Person = @person;

            SET @FechaProceso = DATEADD(DAY, 1, @FechaProceso);
            CONTINUE;
        END;

        SELECT @HingT = CASE
            WHEN @dia = 2 THEN Lunes_Entrada
            WHEN @dia = 3 THEN Martes_Entrada
            WHEN @dia = 4 THEN Miercoles_Entrada
            WHEN @dia = 5 THEN Jueves_Entrada
            WHEN @dia = 6 THEN Viernes_Entrada
            WHEN @dia = 7 THEN Sabado_Entrada
            ELSE Domingo_Entrada
        END
        FROM Horarios
        WHERE IdHorario = @idhorario;

        SELECT @HsalidaT = CASE
            WHEN @dia = 2 THEN Lunes_Salida
            WHEN @dia = 3 THEN Martes_Salida
            WHEN @dia = 4 THEN Miercoles_Salida
            WHEN @dia = 5 THEN Jueves_Salida
            WHEN @dia = 6 THEN Viernes_Salida
            WHEN @dia = 7 THEN Sabado_Salida
            ELSE Domingo_Salida
        END
        FROM Horarios
        WHERE IdHorario = @idhorario;

        SELECT @HEntradaRefriT = CASE
            WHEN @dia = 2 THEN Lunes_EntradaRefri
            WHEN @dia = 3 THEN Martes_EntradaRefri
            WHEN @dia = 4 THEN Miercoles_EntradaRefri
            WHEN @dia = 5 THEN Jueves_EntradaRefri
            WHEN @dia = 6 THEN Viernes_EntradaRefri
            WHEN @dia = 7 THEN Sabado_EntradaRefri
            ELSE Domingo_EntradaRefri
        END
        FROM Horarios
        WHERE IdHorario = @idhorario;

        SELECT @cant = ISNULL(COUNT(*), 0)
        FROM RegistroAsistencia
        WHERE Person = @person
          AND (Company = @cia OR NULLIF(LTRIM(RTRIM(Company)), '') IS NULL)
          AND estado = 'A'
          AND FechaHoraIngreso >= CONVERT(DATE, @FechaProceso)
          AND FechaHoraIngreso < DATEADD(DAY, 1, CONVERT(DATE, @FechaProceso));

        IF @cant = 0
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM PR_VacationDetail vd
                WHERE vd.Person = @person
                  AND vd.Company = @cia
                  AND CONVERT(DATE, @FechaProceso) BETWEEN CONVERT(DATE, vd.Datebegin)
                                                      AND CONVERT(DATE, vd.Dateend)
            )
            BEGIN
                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, MinutosAdicionales, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 0, 'N', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU' WHEN @dia = 3 THEN 'MA' WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU' WHEN @dia = 6 THEN 'VI' WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    'Vacaciones'
                );
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM PR_EmployeeMedicalRest emr
                INNER JOIN PR_MedicalRestType mrt
                    ON mrt.Company = @cia
                   AND mrt.MedicalRestType = emr.MedicalRestType
                WHERE emr.Person = @person
                  AND emr.Company = @cia
                  AND CONVERT(DATE, @FechaProceso) BETWEEN CONVERT(DATE, emr.DateBegin)
                                                      AND CONVERT(DATE, emr.DateEnd)
                  AND LTRIM(RTRIM(mrt.pdt)) IN ('05', '16', '20', '21', '22', '24', '25', '26', '28')
            )
            BEGIN
                SET @motivofalta = (
                    SELECT TOP 1
                        CASE LTRIM(RTRIM(mrt.pdt))
                            WHEN '05' THEN 'Licencia sin goce'
                            WHEN '16' THEN 'Invalidez Temporal'
                            WHEN '20' THEN 'Descanso Médico'
                            WHEN '21' THEN 'Incapacidad Temp.'
                            WHEN '22' THEN 'Descanso Maternidad'
                            WHEN '24' THEN 'Licencia cargo civ.'
                            WHEN '25' THEN 'Licencia sindical'
                            WHEN '26' THEN 'Licencia con goce'
                            WHEN '28' THEN 'Lic. Paternidad'
                            ELSE LEFT(ISNULL(mrt.Description, 'Licencia'), 20)
                        END
                    FROM PR_EmployeeMedicalRest emr
                    INNER JOIN PR_MedicalRestType mrt
                        ON mrt.Company = @cia
                       AND mrt.MedicalRestType = emr.MedicalRestType
                    WHERE emr.Person = @person
                      AND emr.Company = @cia
                      AND CONVERT(DATE, @FechaProceso) BETWEEN CONVERT(DATE, emr.DateBegin)
                                                          AND CONVERT(DATE, emr.DateEnd)
                      AND LTRIM(RTRIM(mrt.pdt)) IN ('05', '16', '20', '21', '22', '24', '25', '26', '28')
                    ORDER BY emr.DateBegin DESC, emr.line DESC
                );

                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, MinutosAdicionales, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 0, 'N', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU' WHEN @dia = 3 THEN 'MA' WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU' WHEN @dia = 6 THEN 'VI' WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    ISNULL(@motivofalta, 'Descanso Médico')
                );
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM CA_Justificacionpersona
                WHERE person = @person
                  AND company = @cia
                  AND @FechaProceso BETWEEN fechainicio AND fechafin
            )
            BEGIN
                SET @motivofalta = (
                    SELECT TOP 1 tj.Descripcion
                    FROM CA_Justificacionpersona jp
                    INNER JOIN CA_TipoJustificacion tj
                        ON jp.idjustificacion = tj.idjustificacion
                    WHERE jp.person = @person
                      AND jp.company = @cia
                      AND @FechaProceso BETWEEN jp.fechainicio AND jp.fechafin
                );

                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, MinutosAdicionales, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 0, 'N', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU' WHEN @dia = 3 THEN 'MA' WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU' WHEN @dia = 6 THEN 'VI' WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    @motivofalta
                );
            END
            ELSE
            BEGIN
                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, MinutosAdicionales, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 0, 'Y', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU' WHEN @dia = 3 THEN 'MA' WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU' WHEN @dia = 6 THEN 'VI' WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    NULL
                );
            END;
        END
        ELSE
        BEGIN
            SELECT @tolerancia = ISNULL(ToleranciaMinutos, 0)
            FROM Horarios
            WHERE IdHorario = @idhorario;

            SELECT @HingR = CAST(MIN(FechaHoraIngreso) AS TIME)
            FROM RegistroAsistencia
            WHERE Person = @person
              AND (Company = @cia OR NULLIF(LTRIM(RTRIM(Company)), '') IS NULL)
              AND estado = 'A'
              AND FechaHoraIngreso >= CONVERT(DATE, @FechaProceso)
              AND FechaHoraIngreso < DATEADD(DAY, 1, CONVERT(DATE, @FechaProceso));

            ;WITH Marcaciones AS (
                SELECT
                    FechaHoraIngreso,
                    ROW_NUMBER() OVER (
                        PARTITION BY Person, CONVERT(DATE, FechaHoraIngreso)
                        ORDER BY FechaHoraIngreso
                    ) AS Orden
                FROM RegistroAsistencia
                WHERE Person = @person
                  AND (Company = @cia OR NULLIF(LTRIM(RTRIM(Company)), '') IS NULL)
                  AND estado = 'A'
                  AND FechaHoraIngreso >= CONVERT(DATE, @FechaProceso)
                  AND FechaHoraIngreso < DATEADD(DAY, 1, CONVERT(DATE, @FechaProceso))
            )
            SELECT
                @Entrada    = MIN(CASE WHEN Orden = 1 THEN FechaHoraIngreso END),
                @SalidaRef  = MIN(CASE WHEN Orden = 2 THEN FechaHoraIngreso END),
                @RetornoRef = MIN(CASE WHEN Orden = 3 THEN FechaHoraIngreso END),
                @Salida     = MIN(CASE WHEN Orden = 4 THEN FechaHoraIngreso END)
            FROM Marcaciones;

            IF @cant = 2
            BEGIN
                SET @Salida = @SalidaRef;
                SET @SalidaRef = NULL;
                SET @RetornoRef = NULL;
            END;

            IF @cant = 3
               AND @RetornoRef IS NOT NULL
               AND @HsalidaT IS NOT NULL
               AND @HEntradaRefriT IS NOT NULL
               AND ABS(DATEDIFF(MINUTE, @HsalidaT, CAST(@RetornoRef AS TIME)))
                   <= ABS(DATEDIFF(MINUTE, @HEntradaRefriT, CAST(@RetornoRef AS TIME)))
            BEGIN
                SET @Salida = @RetornoRef;
                SET @RetornoRef = NULL;
            END;

            SET @MinutosAdicionales = 0;
            IF @Salida IS NOT NULL
               AND @HsalidaT IS NOT NULL
            BEGIN
                SET @SalidaTeorica = DATETIMEFROMPARTS(
                    DATEPART(YEAR, @FechaProceso),
                    DATEPART(MONTH, @FechaProceso),
                    DATEPART(DAY, @FechaProceso),
                    DATEPART(HOUR, @HsalidaT),
                    DATEPART(MINUTE, @HsalidaT),
                    DATEPART(SECOND, @HsalidaT),
                    0
                );
                IF @Salida > @SalidaTeorica
                    SET @MinutosAdicionales = DATEDIFF(MINUTE, @SalidaTeorica, @Salida);
            END;

            INSERT INTO ResumenAsistencia (
                Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                MinutosTarde, MinutosAdicionales, Falta, XLastUser, XLastDate, DiaSem
            )
            VALUES (
                @person, @cia, @FechaProceso, @idhorario, @Entrada, @Salida, @SalidaRef, @RetornoRef,
                CASE
                    WHEN @HingR IS NULL OR @HingT IS NULL THEN 0
                    /* hm_quimica: gracia hasta Entrada+tolerancia; si se excede, cuenta desde Entrada */
                    WHEN DB_NAME() = N'hm_quimica'
                         AND DATEDIFF(MINUTE, @HingT, @HingR) > @tolerancia
                        THEN DATEDIFF(MINUTE, @HingT, @HingR)
                    WHEN DB_NAME() = N'hm_quimica' THEN 0
                    WHEN DATEDIFF(MINUTE, @HingT, @HingR) - @tolerancia > 0
                        THEN DATEDIFF(MINUTE, @HingT, @HingR) - @tolerancia
                    ELSE 0
                END,
                @MinutosAdicionales,
                'N', 'ADMIN', GETDATE(),
                CASE
                    WHEN @dia = 2 THEN 'LU' WHEN @dia = 3 THEN 'MA' WHEN @dia = 4 THEN 'MI'
                    WHEN @dia = 5 THEN 'JU' WHEN @dia = 6 THEN 'VI' WHEN @dia = 7 THEN 'SA'
                    ELSE 'DO'
                END
            );
        END;

        UPDATE SY_Person
        SET FechaProcesamientoCA = GETDATE()
        WHERE Person = @person;

        SET @FechaProceso = DATEADD(DAY, 1, @FechaProceso);
    END;
END;
GO







GO

/* ============================================================================
   08. sql/sp_ca_registrartardanzaplanilla_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_registrartardanzaplanilla_web

  Uso: Consolidado de Asistencia — Registro Planillas (MIN_TARDANZA en PR_EmployeeConcept)

  Parámetros: @cia, @prperiod, @person, @minutos, @xlastuser

  Retorna: Person, Name, Accion (I=insertado, U=actualizado, E=error), Mensaje

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_registrartardanzaplanilla_web]

    @cia       VARCHAR(10),

    @prperiod  VARCHAR(10),

    @person    VARCHAR(20),

    @minutos   INT,

    @xlastuser VARCHAR(20) = NULL

AS

BEGIN

    SET NOCOUNT ON;



    DECLARE @concept         VARCHAR(20);

    DECLARE @payrolltype     VARCHAR(20);

    DECLARE @costcenter      VARCHAR(20);

    DECLARE @costcentercode  VARCHAR(20);

    DECLARE @nombre          VARCHAR(100);

    DECLARE @replicationunit VARCHAR(4);

    DECLARE @periodo         VARCHAR(10);

    DECLARE @accion          CHAR(1) = 'E';

    DECLARE @mensaje         VARCHAR(500) = '';



    SET @cia = LTRIM(RTRIM(ISNULL(@cia, '')));

    SET @person = LTRIM(RTRIM(ISNULL(@person, '')));

    SET @periodo = REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@prperiod, ''))), '-', ''), '/', '');

    IF LEN(@periodo) >= 8 AND ISNUMERIC(LEFT(@periodo, 8)) = 1

        SET @periodo = LEFT(@periodo, 8);

    SET @xlastuser = NULLIF(LTRIM(RTRIM(ISNULL(@xlastuser, ''))), '');

    SET @minutos = ISNULL(@minutos, 0);



    IF @cia = ''

    BEGIN

        SET @mensaje = 'Compañía no válida.';

        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    IF @periodo = ''

    BEGIN

        SET @mensaje = 'Periodo de planilla no válido.';

        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    IF @person = ''

    BEGIN

        SET @mensaje = 'Trabajador no válido.';

        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    IF @minutos < 0

    BEGIN

        SET @mensaje = 'Los minutos de tardanza no pueden ser negativos.';

        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    SELECT TOP 1 @concept = LTRIM(RTRIM(c.Concept))

    FROM PR_Concept c

    WHERE c.Company = @cia

      AND c.FormulaCode = 'MIN_TARDANZA'

      AND c.Status = 'A';



    IF @concept IS NULL OR @concept = ''

    BEGIN

        SET @mensaje = 'No existe concepto activo MIN_TARDANZA para la compañía.';

        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    SELECT

        @payrolltype = LTRIM(RTRIM(e.PayRollType)),

        @costcenter = ISNULL(NULLIF(LTRIM(RTRIM(e.CostCenter)), ''), ''),

        @costcentercode = ISNULL(

            NULLIF(LTRIM(RTRIM(e.CostCenterName)), ''),

            ISNULL(NULLIF(LTRIM(RTRIM(e.CostCenter)), ''), '')

        ),

        @nombre = LTRIM(RTRIM(sp.Name)),

        @replicationunit = NULLIF(LTRIM(RTRIM(sp.ReplicationUnit)), '')

    FROM PR_Employee e

    INNER JOIN SY_Person sp ON sp.Person = e.Person

    WHERE e.Company = @cia

      AND e.Person = @person

      AND e.Status = 'N';



    IF @payrolltype IS NULL

    BEGIN

        SET @mensaje = 'Trabajador no activo en la compañía.';

        SELECT @person AS Person, ISNULL(@nombre, '') AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    IF @payrolltype = ''

    BEGIN

        SET @mensaje = 'El trabajador no tiene tipo de planilla.';

        SELECT @person AS Person, @nombre AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    IF NOT EXISTS (

        SELECT 1

        FROM PR_Period p

        WHERE p.Company = @cia

          AND p.PayRollType = @payrolltype

          AND p.PRPeriod = @periodo

    )

    BEGIN

        SET @mensaje = 'El periodo ' + @periodo + ' no existe para el tipo de planilla del trabajador.';

        SELECT @person AS Person, @nombre AS Name, @accion AS Accion, @mensaje AS Mensaje;

        RETURN;

    END



    IF EXISTS (

        SELECT 1

        FROM PR_EmployeeConcept ec

        WHERE ec.Person = @person

          AND ec.Company = @cia

          AND ec.Concept = @concept

          AND ec.PayRollType = @payrolltype

          AND ec.PRPeriodStart = @periodo

          AND ec.CostCenter = @costcenter

    )

    BEGIN

        UPDATE PR_EmployeeConcept

        SET PRPeriodEnd = @periodo,

            ConceptValue = @minutos,

            ConceptCurrency = 'LO',

            ConceptValueLo = @minutos,

            ConceptValueEx = 0,

            ExchangeRate = 0,

            FlagApplyFormula = 'N',

            FlagFrecuencyType = 'T',

            Application = 'PR',

            PercentageDistribution = 'A',

            XLastUser = @xlastuser,

            XLastDate = GETDATE()

        WHERE Person = @person

          AND Company = @cia

          AND Concept = @concept

          AND PayRollType = @payrolltype

          AND PRPeriodStart = @periodo

          AND CostCenter = @costcenter;



        SET @accion = 'U';

        SET @mensaje = '';

    END

    ELSE

    BEGIN

        INSERT INTO PR_EmployeeConcept (

            Person, Company, Concept, PayRollType, PRPeriodStart, CostCenter,

            PRPeriodEnd, ConceptValue, Application, ConceptCurrency, Comments,

            FlagApplyFormula, FlagFrecuencyType, ReplicationUnit,

            XLastUser, XLastDate, ConceptValueLo, ConceptValueEx, ExchangeRate,

            CostCenterCode, Project, ProjectCode, PercentageDistribution, FlagCopy

        )

        VALUES (

            @person, @cia, @concept, @payrolltype, @periodo, @costcenter,

            @periodo, @minutos, 'PR', 'LO', NULL,

            'N', 'T', @replicationunit,

            @xlastuser, GETDATE(), @minutos, 0, 0,

            @costcentercode, '', '', 'A', NULL

        );



        SET @accion = 'I';

        SET @mensaje = '';

    END



    SELECT @person AS Person, @nombre AS Name, @accion AS Accion, @mensaje AS Mensaje;

END

GO

GO

/* ============================================================================
   09. sql/sp_ca_regularizarfaltas_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_regularizarfaltas_web

  Uso: Consolidado de Asistencia — confirmar Regularizar faltas seleccionadas

  Parámetros:

    @cia        Compañía

    @person     DNI del trabajador

    @fechas     Lista de fechas yyyy-mm-dd separadas por coma

    @comentario Motivo opcional (encargo de empresa, etc.)

    @xlastuser  Usuario que regulariza



  Por cada fecha: crea marcas entrada/salida según horario, registra auditoría

  y reprocesa asistencia del rango afectado.

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_regularizarfaltas_web]

    @cia        CHAR(4),

    @person     VARCHAR(20),

    @fechas     NVARCHAR(MAX),

    @comentario VARCHAR(255) = NULL,

    @xlastuser  VARCHAR(20) = NULL

AS

BEGIN

    SET NOCOUNT ON;



    DECLARE @Fecha DATE;

    DECLARE @idhorario INT;

    DECLARE @dia INT;

    DECLARE @HingT TIME;

    DECLARE @HsalidaT TIME;

    DECLARE @HoraEntrada DATETIME;

    DECLARE @HoraSalida DATETIME;

    DECLARE @IdTrabajador INT;

    DECLARE @motivoMarca VARCHAR(255);

    DECLARE @regularizados INT = 0;

    DECLARE @fechaMin DATE = NULL;

    DECLARE @fechaMax DATE = NULL;

    DECLARE @now DATETIME = GETDATE();



    SET @motivoMarca = LTRIM(RTRIM(ISNULL(@comentario, '')));

    IF @motivoMarca = ''

        SET @motivoMarca = 'Regularización por encargo de empresa';

    ELSE

        SET @motivoMarca = 'Regularización: ' + LEFT(@motivoMarca, 235);



    SET @IdTrabajador = 1;

    SELECT TOP 1 @IdTrabajador = IdTrabajador

    FROM dbo.RegistroAsistencia

    WHERE LTRIM(RTRIM(CAST(Person AS VARCHAR(50)))) = LTRIM(RTRIM(@person))

      AND LTRIM(RTRIM(CAST(company AS CHAR(4)))) = LTRIM(RTRIM(@cia))

    ORDER BY FechaHoraIngreso DESC;



    IF @IdTrabajador IS NULL

        SET @IdTrabajador = 1;



    DECLARE @FechasSel TABLE (Fecha DATE PRIMARY KEY);

    DECLARE @fechasXml XML;



    SET @fechasXml = CAST(

        '<i>' + REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@fechas, ''))), ' ', ''), ',', '</i><i>') + '</i>'

        AS XML

    );



    INSERT INTO @FechasSel (Fecha)

    SELECT DISTINCT CONVERT(DATE, LTRIM(RTRIM(x.item.value('.', 'VARCHAR(20)'))), 23)

    FROM @fechasXml.nodes('/i') AS x(item)

    WHERE LTRIM(RTRIM(x.item.value('.', 'VARCHAR(20)'))) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]';



    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR

        SELECT F.Fecha

        FROM @FechasSel F

        ORDER BY F.Fecha;



    OPEN cur;

    FETCH NEXT FROM cur INTO @Fecha;



    WHILE @@FETCH_STATUS = 0

    BEGIN

        SET @idhorario = NULL;

        SET @HingT = NULL;

        SET @HsalidaT = NULL;



        SELECT TOP 1

            @idhorario = RA.IdHorario

        FROM ResumenAsistencia RA

        WHERE RA.Company = @cia

          AND RA.Person = @person

          AND RA.Fecha = @Fecha

          AND RA.Falta = 'Y';



        IF @idhorario IS NOT NULL

           AND NOT EXISTS (

               SELECT 1

               FROM CA_RegularizacionFalta RF

               WHERE RF.company = @cia

                 AND RF.Person = @person

                 AND RF.Fecha = @Fecha

           )

           AND NOT EXISTS (

               SELECT 1

               FROM RegistroAsistencia R

               WHERE R.Person = @person

                 AND R.company = @cia

                 AND R.estado = 'A'

                 AND R.FechaHoraIngreso >= @Fecha

                 AND R.FechaHoraIngreso < DATEADD(DAY, 1, @Fecha)

           )

        BEGIN

            SET @dia = DATEPART(WEEKDAY, @Fecha);



            SELECT @HingT = CASE

                WHEN @dia = 2 THEN Lunes_Entrada

                WHEN @dia = 3 THEN Martes_Entrada

                WHEN @dia = 4 THEN Miercoles_Entrada

                WHEN @dia = 5 THEN Jueves_Entrada

                WHEN @dia = 6 THEN Viernes_Entrada

                WHEN @dia = 7 THEN Sabado_Entrada

                ELSE Domingo_Entrada

            END

            FROM Horarios

            WHERE IdHorario = @idhorario;



            SELECT @HsalidaT = CASE

                WHEN @dia = 2 THEN Lunes_Salida

                WHEN @dia = 3 THEN Martes_Salida

                WHEN @dia = 4 THEN Miercoles_Salida

                WHEN @dia = 5 THEN Jueves_Salida

                WHEN @dia = 6 THEN Viernes_Salida

                WHEN @dia = 7 THEN Sabado_Salida

                ELSE Domingo_Salida

            END

            FROM Horarios

            WHERE IdHorario = @idhorario;



            IF @HingT IS NOT NULL AND @HsalidaT IS NOT NULL

            BEGIN

                SET @HoraEntrada = DATETIMEFROMPARTS(

                    DATEPART(YEAR, @Fecha),

                    DATEPART(MONTH, @Fecha),

                    DATEPART(DAY, @Fecha),

                    DATEPART(HOUR, @HingT),

                    DATEPART(MINUTE, @HingT),

                    DATEPART(SECOND, @HingT),

                    0

                );



                SET @HoraSalida = DATETIMEFROMPARTS(

                    DATEPART(YEAR, @Fecha),

                    DATEPART(MONTH, @Fecha),

                    DATEPART(DAY, @Fecha),

                    DATEPART(HOUR, @HsalidaT),

                    DATEPART(MINUTE, @HsalidaT),

                    DATEPART(SECOND, @HsalidaT),

                    0

                );



                INSERT INTO dbo.RegistroAsistencia (

                    IdTrabajador,

                    FechaHoraIngreso,

                    RutaFoto,

                    Person,

                    company,

                    xlastuser,

                    xlastdate,

                    flagmanual,

                    MotivoManual,

                    estado

                )

                VALUES

                    (@IdTrabajador, @HoraEntrada, NULL, @person, @cia, @xlastuser, @now, 'Y', @motivoMarca, 'A'),

                    (@IdTrabajador, @HoraSalida, NULL, @person, @cia, @xlastuser, @now, 'Y', @motivoMarca, 'A');



                INSERT INTO dbo.CA_RegularizacionFalta (

                    company,

                    Person,

                    Fecha,

                    IdHorario,

                    HoraEntrada,

                    HoraSalida,

                    Comentario,

                    xlastuser,

                    xlastdate

                )

                VALUES (

                    @cia,

                    @person,

                    @Fecha,

                    @idhorario,

                    @HoraEntrada,

                    @HoraSalida,

                    @comentario,

                    @xlastuser,

                    @now

                );



                SET @regularizados = @regularizados + 1;

                IF @fechaMin IS NULL OR @Fecha < @fechaMin SET @fechaMin = @Fecha;

                IF @fechaMax IS NULL OR @Fecha > @fechaMax SET @fechaMax = @Fecha;

            END;

        END;



        FETCH NEXT FROM cur INTO @Fecha;

    END;



    CLOSE cur;

    DEALLOCATE cur;



    IF @regularizados > 0 AND @fechaMin IS NOT NULL AND @fechaMax IS NOT NULL

    BEGIN

        EXEC [dbo].[sp_ca_procesarasistencia_web]

            @cia = @cia,

            @person = @person,

            @fechaini = @fechaMin,

            @fechafin = @fechaMax;

    END;



    SELECT

        @regularizados AS regularizados,

        @fechaMin AS fechaMin,

        @fechaMax AS fechaMax;

END

GO

GO

/* ============================================================================
   10. sql/sp_ca_reporteconsolidado_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_reporteconsolidado_web

  Uso: Reporte Consolidado de Asistencia (POST /api/reportes/consolidado-asistencia)

  Parámetros: @cia, @person ('0' = todos), @fechaini, @fechafin

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_reporteconsolidado_web]

    @cia       CHAR(4),

    @person    VARCHAR(20),

    @fechaini  DATETIME,

    @fechafin  DATETIME

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        ResumenAsistencia.Person,

        SY_Person.Name,

        SUM(MinutosTarde) AS tardanza,

        SUM(CASE WHEN ISNULL(MinutosTarde, 0) > 0 THEN 1 ELSE 0 END) AS diasTardanza,

        SUM(CASE WHEN Falta = 'Y' THEN 1 ELSE 0 END) AS faltas,

        SUM(MinutosAdicionales) AS Adicional

    FROM ResumenAsistencia

    INNER JOIN SY_Person

        ON ResumenAsistencia.Person = SY_Person.Person

    WHERE ResumenAsistencia.Company = @cia

      AND (@person = '0' OR ResumenAsistencia.Person = @person)

      AND Fecha BETWEEN CONVERT(DATE, @fechaini) AND CONVERT(DATE, @fechafin)

    GROUP BY

        ResumenAsistencia.Person,

        SY_Person.Name

    ORDER BY

        SY_Person.Name;

END

GO

GO

/* ============================================================================
   11. sql/sp_ca_reporteresumenasistencia_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_ReporteResumenAsistencia_web

  Uso: Reporte Resumen de Asistencia (POST /api/reportes/resumen-asistencia)

  Parámetros: @cia, @fechaini, @fechafin, @person ('0' = todos)

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_ReporteResumenAsistencia_web]

    @cia       CHAR(4),

    @fechaini  DATETIME,

    @fechafin  DATETIME,

    @person    VARCHAR(20)

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        ResumenAsistencia.Person,

        SY_Person.Name,

        Fecha,

        DiaSem,

        Horarios.NombreHorario,

        Entrada,

        SalidaRefri,

        EntradaRefri,

        Salida,

        CASE WHEN Falta = 'Y' THEN 'Si' ELSE 'No' END AS falta,

        CASE WHEN ISNULL(MinutosTarde, 0) > 0 THEN 'Si' ELSE 'No' END AS tardanza,

        MinutosTarde AS minutostarde,

        motivo,

        MinutosAdicionales

    FROM ResumenAsistencia

    INNER JOIN SY_Person

        ON ResumenAsistencia.Person = SY_Person.Person

       AND ResumenAsistencia.Company = @cia

    INNER JOIN Horarios

        ON ResumenAsistencia.IdHorario = Horarios.IdHorario

       AND Horarios.Company = @cia

    WHERE Fecha BETWEEN @fechaini AND @fechafin

      AND (@person = '0' OR ResumenAsistencia.Person = @person)

    ORDER BY SY_Person.Name,

             Fecha;

END;

GO

GO

/* ============================================================================
   12. sql/sp_ca_selectorperiodosplanilla_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_selectorperiodosplanilla_web

  Uso: Consolidado de Asistencia — selector de periodos para Registro Planillas

  Parámetros: @cia

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_selectorperiodosplanilla_web]

    @cia VARCHAR(10)

AS

BEGIN

    SET NOCOUNT ON;



    SET @cia = LTRIM(RTRIM(ISNULL(@cia, '')));



    SELECT DISTINCT p.PRPeriod

    FROM PR_Period p

    WHERE p.Company = @cia

    ORDER BY p.PRPeriod DESC;

END

GO

GO

/* ============================================================================
   13. sql/sp_ca_validarmarcasimpares_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_validarmarcasimpares_web

  Uso: Procesar Asistencia — advertencias al consultar (días con cantidad impar de marcas)

  Parámetros: @cia, @fechaini, @fechafin

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_validarmarcasimpares_web]

    @cia       CHAR(4),

    @fechaini  DATETIME,

    @fechafin  DATETIME

AS

BEGIN

    SET NOCOUNT ON;



    DECLARE @dIni DATE = CONVERT(DATE, @fechaini);

    DECLARE @dFin DATE = CONVERT(DATE, @fechafin);



    SELECT

        P.Person,

        P.Name,

        CONVERT(DATE, R.FechaHoraIngreso) AS FechaMarca,

        COUNT(*) AS CantidadMarcas

    FROM RegistroAsistencia R

    INNER JOIN SY_Person P

        ON R.Person = P.Person

    INNER JOIN PR_Employee E

        ON P.Person = E.Person

       AND E.Company = @cia

       AND E.Status = 'N'

    WHERE R.Company = @cia

      AND R.estado = 'A'

      AND CONVERT(DATE, R.FechaHoraIngreso) BETWEEN @dIni AND @dFin

    GROUP BY

        P.Person,

        P.Name,

        CONVERT(DATE, R.FechaHoraIngreso)

    HAVING COUNT(*) % 2 = 1

    ORDER BY

        P.Name,

        FechaMarca;

END

GO

GO

/* ============================================================================
   14. sql/sp_ca_validarmarcassinhorario_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_ca_validarmarcassinhorario_web

  Uso: Procesar Asistencia — advertencias al consultar (marcas sin horario asignado)

  Parámetros: @cia, @fechaini, @fechafin

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_ca_validarmarcassinhorario_web]

    @cia       CHAR(4),

    @fechaini  DATETIME,

    @fechafin  DATETIME

AS

BEGIN

    SET NOCOUNT ON;



    DECLARE @dIni DATE = CONVERT(DATE, @fechaini);

    DECLARE @dFin DATE = CONVERT(DATE, @fechafin);



    SELECT

        P.Person,

        P.Name,

        CONVERT(DATE, R.FechaHoraIngreso) AS FechaMarca

    FROM RegistroAsistencia R

    INNER JOIN SY_Person P

        ON R.Person = P.Person

    INNER JOIN PR_Employee E

        ON P.Person = E.Person

       AND E.Company = @cia

       AND E.Status = 'N'

    WHERE R.Company = @cia

      AND R.estado = 'A'

      AND CONVERT(DATE, R.FechaHoraIngreso) BETWEEN @dIni AND @dFin

      AND NOT EXISTS (

          SELECT 1

          FROM AsignacionHorarios AH

          WHERE AH.Person = R.Person

            AND AH.Company = @cia

            AND CONVERT(DATE, R.FechaHoraIngreso) BETWEEN AH.FechaInicio

                AND ISNULL(AH.FechaFin, CONVERT(DATE, '99991231'))

      )

    GROUP BY

        P.Person,

        P.Name,

        CONVERT(DATE, R.FechaHoraIngreso)

    ORDER BY

        P.Name,

        FechaMarca;

END

GO

GO

/* ============================================================================
   15. sql/sp_pr_actualizardescarga_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_Actualizardescarga_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person, @tipodocumento, @prperiod



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_Actualizardescarga_web @cia, @person, @tipodocumento, @prperiod

GO

GO

/* ============================================================================
   16. sql/sp_pr_aprobarsolicitud_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_AprobarSolicitud_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person, @controlyear, @line, @userid



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_AprobarSolicitud_web @cia, @person, @controlyear, @line, @userid

GO

GO

/* ============================================================================
   17. sql/sp_pr_aprobarsolicitudespendientes_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_AprobarSolicitudesPendientes_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @name, @estado



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_AprobarSolicitudesPendientes_web @cia, @name, @estado

GO

GO

/* ============================================================================
   18. sql/sp_pr_ausenciasperson_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_ausenciasperson_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_ausenciasperson_web @cia, @person

GO

GO

/* ============================================================================
   19. sql/sp_pr_cambiarpassword_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_CambiarPassword_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @userid, @clave_ant, @clave_nueva



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_CambiarPassword_web @userid, @clave_ant, @clave_nueva

GO

GO

/* ============================================================================
   20. sql/sp_pr_constanciatrabajo_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_constanciatrabajo_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @person, @cia



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_constanciatrabajo_web @person, @cia

GO

GO

/* ============================================================================
   21. sql/sp_pr_datosusuario_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_datosusuario_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @userid



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_datosusuario_web @userid

GO

GO

/* ============================================================================
   22. sql/sp_pr_detalleboletaaportes_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_detalleboletaaportes_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @process, @payrolltype, @period, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_detalleboletaaportes_web @cia, @process, @payrolltype, @period, @person

GO

GO

/* ============================================================================
   23. sql/sp_pr_detalleboletadescuentos_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_detalleboletadescuentos_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @process, @payrolltype, @period, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_detalleboletadescuentos_web @cia, @process, @payrolltype, @period, @person

GO

GO

/* ============================================================================
   24. sql/sp_pr_detalleboletaingresos_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_detalleboletaingresos_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @process, @payrolltype, @period, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_detalleboletaingresos_web @cia, @process, @payrolltype, @period, @person

GO

GO

/* ============================================================================
   25. sql/sp_pr_eliminarsolicitudpermiso_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_EliminarSolicitudPermiso_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person, @line



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_EliminarSolicitudPermiso_web @cia, @person, @line

GO

GO

/* ============================================================================
   26. sql/sp_pr_enviocomprobantes_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_enviocomprobantes_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @tipodoc, @prperiod



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_enviocomprobantes_web @cia, @tipodoc, @prperiod

GO

GO

/* ============================================================================
   27. sql/sp_pr_filtroperiodos_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_FiltroPeriodos_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_FiltroPeriodos_web @cia

GO

GO

/* ============================================================================
   28. sql/sp_pr_generarboleta_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_generarboleta_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @process, @payrolltype, @period, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_generarboleta_web @cia, @process, @payrolltype, @period, @person

GO

GO

/* ============================================================================
   29. sql/sp_pr_horariosasignados_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_horariosasignados_web

  Uso: Listado de horarios asignados por compañía (Asignación de Horarios)

  Parámetros: @cia

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_pr_horariosasignados_web]

    @cia VARCHAR(4)

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        SY_Person.Person AS person,

        SY_Person.Name AS name,

        Horarios.NombreHorario,

        AsignacionHorarios.FechaInicio AS fechinicio,

        AsignacionHorarios.FechaFin AS fechafin,

        AsignacionHorarios.IdAsignacion

    FROM AsignacionHorarios

    INNER JOIN Horarios

        ON AsignacionHorarios.IdHorario = Horarios.IdHorario

       AND Horarios.Company = @cia

    INNER JOIN SY_Person

        ON AsignacionHorarios.Person = SY_Person.Person

    WHERE AsignacionHorarios.Company = @cia

    ORDER BY SY_Person.Name;

END;

GO

GO

/* ============================================================================
   30. sql/sp_pr_listadocumentos_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_listadocumentos_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person, @tipodoc



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_listadocumentos_web @cia, @person, @tipodoc

GO

GO

/* ============================================================================
   31. sql/sp_pr_listadogenerarboletas_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_listadogenerarboletas_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @payrolltype, @processtype, @period, @name



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_listadogenerarboletas_web @cia, @payrolltype, @processtype, @period, @name

GO

GO

/* ============================================================================
   32. sql/sp_pr_listadomarcas_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_listadomarcas_web

  Uso: Gestión de Marcas (database.get_listado_marcas / api/marcas/listar)

  Parámetros: @cia, @Fechainicio, @FechaFin, @person ('0' = todos los trabajadores)

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_pr_listadomarcas_web]

    @cia          CHAR(4),

    @Fechainicio  DATETIME,

    @FechaFin     DATETIME,

    @person       VARCHAR(20)

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        R.IdRegistro,

        P.Person AS DNI,

        P.Name AS Nombre,

        /* Lunes=1 … Domingo=7, independiente de @@DATEFIRST del servidor */

        CASE ((DATEPART(WEEKDAY, CONVERT(DATE, R.FechaHoraIngreso)) + @@DATEFIRST - 2) % 7) + 1

            WHEN 1 THEN 'LU'

            WHEN 2 THEN 'MA'

            WHEN 3 THEN 'MI'

            WHEN 4 THEN 'JU'

            WHEN 5 THEN 'VI'

            WHEN 6 THEN 'SA'

            ELSE 'DO'

        END AS diasemana,

        R.FechaHoraIngreso AS FechaHoraIngreso,

        CONVERT(VARCHAR(5), R.FechaHoraIngreso, 108) AS hora,

        PR_Position.Description AS cargo,

        R.RutaFoto

    FROM RegistroAsistencia R

    INNER JOIN SY_Person P

        ON R.Person = P.Person

    INNER JOIN PR_Employee E

        ON P.Person = E.Person

       AND E.Company = @cia

    LEFT JOIN PR_Position

        ON E.Position = PR_Position.Position

    WHERE CONVERT(VARCHAR(8), R.FechaHoraIngreso, 112)

          BETWEEN CONVERT(VARCHAR(8), @Fechainicio, 112)

              AND CONVERT(VARCHAR(8), @FechaFin, 112)

      AND (@person = '0' OR R.Person = @person)

      AND R.estado = 'A'

    ORDER BY P.Name, R.FechaHoraIngreso;

END;

GO

GO

/* ============================================================================
   33. sql/sp_pr_listaenvioalertas_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_listaenvioalertas_web

  Uso: Configurar Alertas (GET /api/alertas/lista)

  Parámetros: @cia

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_pr_listaenvioalertas_web]

    @cia VARCHAR(4)

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        SY_Person.Person,

        SY_Person.Name,

        SY_Person.EMail,

        CA_ConfiguracionAlertas.RecibeAlertas AS recibealertas

    FROM CA_ConfiguracionAlertas

    INNER JOIN SY_Person

        ON CA_ConfiguracionAlertas.Person = SY_Person.Person

    WHERE CA_ConfiguracionAlertas.Company = @cia

    ORDER BY

        SY_Person.Name;

END

GO

GO

/* ============================================================================
   34. sql/sp_pr_listarsolicitudpermiso_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_ListarSolicitudPermiso_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_ListarSolicitudPermiso_web @cia, @person

GO

GO

/* ============================================================================
   35. sql/sp_pr_registrarcomprobantes_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_registrarcomprobantes_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @payrolltype, @processtype, @period, @person, @userid, @filename, @tipo



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_registrarcomprobantes_web @cia, @payrolltype, @processtype, @period, @person, @userid, @filename, @tipo

GO

GO

/* ============================================================================
   36. sql/sp_pr_registrarsolicitudpermiso_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_RegistrarSolicitudPermiso_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person, @userid, @controlyear, @fechaini, @fechaFin, @comentario



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_RegistrarSolicitudPermiso_web @cia, @person, @userid, @controlyear, @fechaini, @fechaFin, @comentario

GO

GO

/* ============================================================================
   37. sql/sp_pr_reportedescargas_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_reportedescargas_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @tipodoc, @prperiod



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_reportedescargas_web @cia, @tipodoc, @prperiod

GO

GO

/* ============================================================================
   38. sql/sp_pr_reporteplame_total_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_reporteplame_total_web

  Uso en proyecto: app.py

  Parámetros (desde Python): @cia, @payrolltype, @period, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_reporteplame_total_web @cia, @payrolltype, @period, @person

GO

GO

/* ============================================================================
   39. sql/sp_pr_reporteplamevertical_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_reporteplamevertical_web

  Uso en proyecto: app.py

  Parámetros (desde Python): @cia, @payrolltype, @process, @period, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_reporteplamevertical_web @cia, @payrolltype, @process, @period, @person

GO

GO

/* ============================================================================
   40. sql/sp_pr_reportepromedioliquidacion.sql
   ============================================================================ */
/*

  Procedimiento: SP_PR_ReportePromedioLiquidacion

  Uso en proyecto: app.py

  Parámetros (desde Python): @cia, @payrolltype, @period, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC SP_PR_ReportePromedioLiquidacion @cia, @payrolltype, @period, @person

GO

GO

/* ============================================================================
   41. sql/sp_pr_selectorcompanias_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_selectorcompanias_web

  Uso: Selector de compañías (Gestión de Marcas, alertas, horarios, reportes, etc.)

  Parámetros: ninguno

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_pr_selectorcompanias_web]

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        Company,

        description

    FROM SY_Company

    WHERE status = 'A'

    ORDER BY Company;

END;

GO

GO

/* ============================================================================
   42. sql/sp_pr_selectorperiodos_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_selectorperiodos_web

  Uso en proyecto: app.py, database.py

  Parámetros (desde Python): @cia, @payrolltype, @processtype



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_selectorperiodos_web @cia, @payrolltype, @processtype

GO

GO

/* ============================================================================
   43. sql/sp_pr_selectorpersonas_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_selectorpersonas_web

  Uso: Selector de trabajadores por compañía (Gestión de Marcas, reportes, etc.)

  Parámetros: @cia

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_pr_selectorpersonas_web]

    @cia VARCHAR(4)

AS

BEGIN

    SET NOCOUNT ON;



    SELECT

        PR_Employee.Person,

        SY_Person.Name

    FROM SY_Person

    INNER JOIN PR_Employee

        ON SY_Person.Person = PR_Employee.Person

       AND PR_Employee.Status = 'N'

       AND PR_Employee.Company = @cia

    ORDER BY SY_Person.Name;

END;

GO

GO

/* ============================================================================
   44. sql/sp_pr_selectorpersonasca_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_selectorpersonasCA_web

  Uso: Procesar Asistencia (api/asistencia/personas — grilla de trabajadores)

  Parámetros: @cia, @fechaini, @fechafin

*/

SET ANSI_NULLS ON;

GO

SET QUOTED_IDENTIFIER ON;

GO



CREATE OR ALTER PROCEDURE [dbo].[sp_pr_selectorpersonasCA_web]

    @cia       VARCHAR(4),

    @fechaini  DATETIME,

    @fechafin  DATETIME

AS

BEGIN

    SET NOCOUNT ON;



    DECLARE @dIni DATE = CONVERT(DATE, @fechaini);

    DECLARE @dFin DATE = CONVERT(DATE, @fechafin);



    SELECT

        e.Person,

        p.[Name],

        ISNULL(e.ReEntryDate, e.EntryDate) AS EntryDate,

        e.CeaseDate AS CeaseDate,

        p.FechaProcesamientoCA AS ultimafecha,

        h.NombreHorario AS Horario

    FROM SY_Person AS p

    INNER JOIN PR_Employee AS e

        ON p.Person = e.Person

       AND e.Status = 'N'

       AND e.Company = @cia

    OUTER APPLY (

        SELECT TOP (1)

            ah.IdHorario

        FROM AsignacionHorarios AS ah

        WHERE ah.Person = p.Person

          AND ah.Company = @cia

          AND CONVERT(DATE, ah.FechaInicio) <= @dFin

          AND CONVERT(DATE, ISNULL(ah.FechaFin, '99991231')) >= @dIni

        ORDER BY ah.FechaInicio DESC,

                 ah.IdAsignacion DESC

    ) AS asig

    LEFT JOIN Horarios AS h

        ON h.IdHorario = asig.IdHorario

       AND h.Company = @cia

    ORDER BY p.[Name];

END;

GO

GO

/* ============================================================================
   45. sql/sp_pr_selectorplanillas_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_selectorplanillas_web

  Uso en proyecto: app.py, database.py

  Parámetros (desde Python): @cia



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_selectorplanillas_web @cia

GO

GO

/* ============================================================================
   46. sql/sp_pr_selectorprocesos_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_selectorprocesos_web

  Uso en proyecto: app.py, database.py

  Parámetros (desde Python): @cia, @payrolltype



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_selectorprocesos_web @cia, @payrolltype

GO

GO

/* ============================================================================
   47. sql/sp_pr_selectortipojus_web.sql
   ============================================================================ */
SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



CREATE OR CREATE OR ALTER PROCEDURE [dbo].[sp_pr_selectortipojus_web]


as


begin


    select idjustificacion, descripcion, abreviatura from ca_tipojustificacion


end

GO

/* ============================================================================
   48. sql/sp_pr_vacacionesperson_web.sql
   ============================================================================ */
/*

  Procedimiento: sp_pr_vacacionesperson_web

  Uso en proyecto: database.py

  Parámetros (desde Python): @cia, @person



  NOTA: Este script es un marcador. El procedimiento no se encontró en la base

  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:

  clic derecho en el SP → Script Stored Procedure as → ALTER To.

*/

SET ANSI_NULLS ON

GO

SET QUOTED_IDENTIFIER ON

GO



-- TODO: pegar aquí la definición CREATE OR ALTER PROCEDURE desde SQL Server

-- EXEC sp_pr_vacacionesperson_web @cia, @person

GO

GO
