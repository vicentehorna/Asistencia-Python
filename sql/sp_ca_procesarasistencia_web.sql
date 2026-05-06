/*
  Procedimiento: sp_ca_procesarasistencia_web
  - Procesa asistencia por persona y rango de fechas.
  - Sin marcas: vacaciones -> descanso médico (PDT <> '07', motivo = PR_MedicalRestType.Description)
    -> justificación CA -> falta.
  - Con marcas: siempre inserta resumen con cálculo de tardanza.
  Ejecutar en la base de datos correspondiente (ajustar esquema si no es dbo).
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_ca_procesarasistencia_web]
    @cia CHAR(4),
    @person VARCHAR(20),
    @fechaini DATETIME,
    @fechafin DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FechaProceso DATE;
    DECLARE @idhorario INT,
            @cant INT,
            @tolerancia INT,
            @dia INT;
    DECLARE @HingT TIME,
            @HingR TIME;
    DECLARE @Entrada DATETIME,
            @SalidaRef DATETIME,
            @RetornoRef DATETIME,
            @Salida DATETIME;
    DECLARE @motivofalta VARCHAR(100);
    DECLARE @motivoDescansoMed VARCHAR(100);

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
        SET @Entrada = NULL;
        SET @SalidaRef = NULL;
        SET @RetornoRef = NULL;
        SET @Salida = NULL;
        SET @motivofalta = NULL;
        SET @motivoDescansoMed = NULL;

        -- 1) Horario asignado en la fecha
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

        -- 2) Feriado activo
        IF EXISTS (
            SELECT 1
            FROM SY_Holiday
            WHERE HolidayDate = @FechaProceso
              AND Status = 'A'
        )
        BEGIN
            SET @FechaProceso = DATEADD(DAY, 1, @FechaProceso);
            CONTINUE;
        END;

        -- 3) Un horario asignado (el más reciente por inicio)
        SELECT TOP (1)
            @idhorario = IdHorario
        FROM AsignacionHorarios
        WHERE Person = @person
          AND Company = @cia
          AND @FechaProceso BETWEEN FechaInicio AND ISNULL(FechaFin, '99991231')
        ORDER BY FechaInicio DESC,
                 IdAsignacion DESC;

        -- 4) Día laborable según horario
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

        -- 5) Hora teórica de ingreso
        SELECT @HingT =
               CASE
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

        -- 6) Cantidad de marcas del día
        SELECT @cant = COUNT_BIG(*)
        FROM RegistroAsistencia
        WHERE Person = @person
          AND Company = @cia
          AND FechaHoraIngreso >= @FechaProceso
          AND FechaHoraIngreso < DATEADD(DAY, 1, @FechaProceso);

        IF @cant = 0
        BEGIN
            -- Sin marcas
            IF EXISTS (
                SELECT 1
                FROM PR_VacationDetail vd
                WHERE vd.Person = @person
                  AND vd.Company = @cia
                  AND @FechaProceso BETWEEN CONVERT(DATE, vd.Datebegin) AND CONVERT(DATE, vd.Dateend)
            )
            BEGIN
                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 'N', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU'
                        WHEN @dia = 3 THEN 'MA'
                        WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU'
                        WHEN @dia = 6 THEN 'VI'
                        WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    'Vacaciones'
                );
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM PR_EmployeeMedicalRest mr
                INNER JOIN PR_MedicalRestType mrt
                    ON mrt.MedicalRestType = mr.MedicalRestType
                   AND (mrt.Company IS NULL OR mrt.Company = mr.Company)
                WHERE mr.Person = @person
                  AND mr.Company = @cia
                  AND @FechaProceso BETWEEN CONVERT(DATE, mr.DateBegin) AND CONVERT(DATE, mr.DateEnd)
                  AND ISNULL(LTRIM(RTRIM(COALESCE(mrt.pdt, mr.pdt))), '') <> '07'
                  AND NULLIF(LTRIM(RTRIM(mrt.Description)), '') IS NOT NULL
            )
            BEGIN
                SELECT TOP (1)
                    @motivoDescansoMed = NULLIF(LTRIM(RTRIM(mrt.Description)), '')
                FROM PR_EmployeeMedicalRest mr
                INNER JOIN PR_MedicalRestType mrt
                    ON mrt.MedicalRestType = mr.MedicalRestType
                   AND (mrt.Company IS NULL OR mrt.Company = mr.Company)
                WHERE mr.Person = @person
                  AND mr.Company = @cia
                  AND @FechaProceso BETWEEN CONVERT(DATE, mr.DateBegin) AND CONVERT(DATE, mr.DateEnd)
                  AND ISNULL(LTRIM(RTRIM(COALESCE(mrt.pdt, mr.pdt))), '') <> '07'
                  AND NULLIF(LTRIM(RTRIM(mrt.Description)), '') IS NOT NULL
                ORDER BY mr.DateBegin DESC,
                         mr.line DESC;

                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 'N', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU'
                        WHEN @dia = 3 THEN 'MA'
                        WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU'
                        WHEN @dia = 6 THEN 'VI'
                        WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    @motivoDescansoMed
                );
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM CA_JustificacionPersona
                WHERE Person = @person
                  AND company = @cia
                  AND @FechaProceso BETWEEN FechaInicio AND FechaFin
            )
            BEGIN
                SELECT TOP (1)
                    @motivofalta = tj.Abreviatura
                FROM CA_JustificacionPersona jp
                INNER JOIN CA_TipoJustificacion tj
                    ON jp.IdJustificacion = tj.IdJustificacion
                WHERE jp.Person = @person
                  AND jp.company = @cia
                  AND @FechaProceso BETWEEN jp.FechaInicio AND jp.FechaFin
                ORDER BY jp.FechaInicio DESC;

                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 'N', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU'
                        WHEN @dia = 3 THEN 'MA'
                        WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU'
                        WHEN @dia = 6 THEN 'VI'
                        WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    @motivofalta
                );
            END
            ELSE
            BEGIN
                INSERT INTO ResumenAsistencia (
                    Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                    MinutosTarde, Falta, XLastUser, XLastDate, DiaSem, motivo
                )
                VALUES (
                    @person, @cia, @FechaProceso, @idhorario, NULL, NULL, NULL, NULL,
                    0, 'Y', 'ADMIN', GETDATE(),
                    CASE
                        WHEN @dia = 2 THEN 'LU'
                        WHEN @dia = 3 THEN 'MA'
                        WHEN @dia = 4 THEN 'MI'
                        WHEN @dia = 5 THEN 'JU'
                        WHEN @dia = 6 THEN 'VI'
                        WHEN @dia = 7 THEN 'SA'
                        ELSE 'DO'
                    END,
                    NULL
                );
            END
        END
        ELSE
        BEGIN
            SELECT @tolerancia = ISNULL(ToleranciaMinutos, 0)
            FROM Horarios
            WHERE IdHorario = @idhorario;

            SELECT @HingR = CAST(MIN(FechaHoraIngreso) AS TIME)
            FROM RegistroAsistencia
            WHERE Person = @person
              AND Company = @cia
              AND FechaHoraIngreso >= @FechaProceso
              AND FechaHoraIngreso < DATEADD(DAY, 1, @FechaProceso);

            ;WITH Marcaciones AS (
                SELECT
                    FechaHoraIngreso,
                    ROW_NUMBER() OVER (
                        PARTITION BY Person, CONVERT(DATE, FechaHoraIngreso)
                        ORDER BY FechaHoraIngreso
                    ) AS Orden
                FROM RegistroAsistencia
                WHERE Person = @person
                  AND Company = @cia
                  AND FechaHoraIngreso >= @FechaProceso
                  AND FechaHoraIngreso < DATEADD(DAY, 1, @FechaProceso)
            )
            SELECT
                @Entrada = MIN(CASE WHEN Orden = 1 THEN FechaHoraIngreso END),
                @SalidaRef = MIN(CASE WHEN Orden = 2 THEN FechaHoraIngreso END),
                @RetornoRef = MIN(CASE WHEN Orden = 3 THEN FechaHoraIngreso END),
                @Salida = MIN(CASE WHEN Orden = 4 THEN FechaHoraIngreso END)
            FROM Marcaciones;

            IF @cant = 2
            BEGIN
                SET @SalidaRef = NULL;
                SET @RetornoRef = NULL;
            END;

            INSERT INTO ResumenAsistencia (
                Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                MinutosTarde, Falta, XLastUser, XLastDate, DiaSem
            )
            VALUES (
                @person, @cia, @FechaProceso, @idhorario, @Entrada, @Salida, @SalidaRef, @RetornoRef,
                CASE
                    WHEN @HingR IS NULL
                         OR @HingT IS NULL THEN 0
                    WHEN DATEDIFF(MINUTE, @HingT, @HingR) - @tolerancia > 0
                        THEN DATEDIFF(MINUTE, @HingT, @HingR) - @tolerancia
                    ELSE 0
                END,
                'N', 'ADMIN', GETDATE(),
                CASE
                    WHEN @dia = 2 THEN 'LU'
                    WHEN @dia = 3 THEN 'MA'
                    WHEN @dia = 4 THEN 'MI'
                    WHEN @dia = 5 THEN 'JU'
                    WHEN @dia = 6 THEN 'VI'
                    WHEN @dia = 7 THEN 'SA'
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
