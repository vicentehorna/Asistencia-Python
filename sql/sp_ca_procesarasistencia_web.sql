/*
  Procedimiento: sp_ca_procesarasistencia_web
  Uso: Procesar Asistencia — botón Iniciar Proceso (api/asistencia/procesar_individual)
  Parámetros: @cia, @person, @fechaini, @fechafin

  Tablas: ResumenAsistencia, AsignacionHorarios, Horarios, SY_Holiday, CA_Feriados,
          RegistroAsistencia, PR_VacationDetail, PR_EmployeeMedicalRest, PR_MedicalRestType,
          CA_JustificacionPersona, CA_TipoJustificacion, SY_Person

  Feriados (SY_Holiday Status=A o CA_Feriados): se registran en resumen con Falta='N' y Motivo='Feriado'.
  Sin marcas: vacaciones -> descanso médico/incapacidad/licencia
  (PDT 05,16,20,21,22,24,25,26,28) -> justificación CA -> falta.
  Sin asignación de horario vigente en el día: no se genera fila en el resumen.
  RegistroAsistencia: solo marcas con estado = 'A' (activas). Las inactivas (I) se ignoran.
  Marcas con Company NULL/vacío también se consideran (marcador de hm_quimica no graba compañía).
  Con 2 marcas: la 2.ª es salida. Con 3 marcas: si la 3.ª está más cerca de la salida
  teórica que del retorno de refrigerio, se toma como salida y E. refri queda vacía.
  Tardanza (hm_quimica): si llega dentro de ToleranciaMinutos desde la hora de entrada -> 0;
  si se pasa, MinutosTarde = minutos desde la hora de entrada (no se resta la tolerancia).
  Refrigerio (solo hm_quimica, 4 marcas): si (E.refri - S.refri) > 60 min, el exceso se suma a MinutosTarde.
  Tardanza (otras BD): minutos desde entrada menos ToleranciaMinutos (máx. 0).
  Con justificación CA del día: no se registra tardanza (MinutosTarde=0) y Motivo = tipo de justificación.
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
    DECLARE @MinutosTarde INT;
    DECLARE @MinutosRefri INT;

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
        SET @MinutosTarde = 0;
        SET @MinutosRefri = 0;

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

            /* Justificación del día: anula tardanza y deja el motivo (aunque haya marcas). */
            SET @motivofalta = (
                SELECT TOP 1 LEFT(ISNULL(tj.Descripcion, 'Justificación'), 20)
                FROM CA_Justificacionpersona jp
                INNER JOIN CA_TipoJustificacion tj
                    ON jp.idjustificacion = tj.idjustificacion
                WHERE jp.person = @person
                  AND jp.company = @cia
                  AND CONVERT(DATE, @FechaProceso) BETWEEN CONVERT(DATE, jp.fechainicio)
                                                      AND CONVERT(DATE, jp.fechafin)
                ORDER BY jp.fechainicio DESC, jp.Id DESC
            );

            SET @MinutosTarde = 0;
            IF @motivofalta IS NULL
            BEGIN
                IF @HingR IS NOT NULL AND @HingT IS NOT NULL
                BEGIN
                    IF DB_NAME() = N'hm_quimica'
                    BEGIN
                        IF DATEDIFF(MINUTE, @HingT, @HingR) > @tolerancia
                            SET @MinutosTarde = DATEDIFF(MINUTE, @HingT, @HingR);
                    END
                    ELSE IF DATEDIFF(MINUTE, @HingT, @HingR) - @tolerancia > 0
                        SET @MinutosTarde = DATEDIFF(MINUTE, @HingT, @HingR) - @tolerancia;
                END;

                /* hm_quimica: 4 marcas y refrigerio > 60 min → el exceso es tardanza. */
                IF DB_NAME() = N'hm_quimica'
                   AND @cant = 4
                   AND @SalidaRef IS NOT NULL
                   AND @RetornoRef IS NOT NULL
                BEGIN
                    SET @MinutosRefri = DATEDIFF(MINUTE, @SalidaRef, @RetornoRef);
                    IF @MinutosRefri > 60
                        SET @MinutosTarde = @MinutosTarde + (@MinutosRefri - 60);
                END;
            END;

            INSERT INTO ResumenAsistencia (
                Person, Company, Fecha, IdHorario, Entrada, Salida, SalidaRefri, EntradaRefri,
                MinutosTarde, MinutosAdicionales, Falta, XLastUser, XLastDate, DiaSem, motivo
            )
            VALUES (
                @person, @cia, @FechaProceso, @idhorario, @Entrada, @Salida, @SalidaRef, @RetornoRef,
                @MinutosTarde,
                @MinutosAdicionales,
                'N', 'ADMIN', GETDATE(),
                CASE
                    WHEN @dia = 2 THEN 'LU' WHEN @dia = 3 THEN 'MA' WHEN @dia = 4 THEN 'MI'
                    WHEN @dia = 5 THEN 'JU' WHEN @dia = 6 THEN 'VI' WHEN @dia = 7 THEN 'SA'
                    ELSE 'DO'
                END,
                @motivofalta
            );
        END;

        UPDATE SY_Person
        SET FechaProcesamientoCA = GETDATE()
        WHERE Person = @person;

        SET @FechaProceso = DATEADD(DAY, 1, @FechaProceso);
    END;
END;
GO
