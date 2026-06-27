/*
  Procedimiento: sp_ca_listarfaltasregularizar_web
  Uso: Consolidado de Asistencia — modal Regularizar (días con falta del trabajador)
  Parámetros: @cia, @person, @fechaini, @fechafin
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_ca_listarfaltasregularizar_web]
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
