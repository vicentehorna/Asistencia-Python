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
