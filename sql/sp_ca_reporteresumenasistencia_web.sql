/*
  Procedimiento: sp_ca_ReporteResumenAsistencia_web
  Uso: Reporte Resumen de Asistencia (POST /api/reportes/resumen-asistencia)
  Parámetros: @cia, @fechaini, @fechafin, @person ('0' = todos)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_ca_ReporteResumenAsistencia_web]
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
        MinutosTarde AS minutostarde,
        motivo,
        MinutosAdicionales
    FROM ResumenAsistencia
    INNER JOIN SY_Person
        ON ResumenAsistencia.Person = SY_Person.Person
       AND ResumenAsistencia.Company = @cia
    INNER JOIN Horarios
        ON ResumenAsistencia.IdHorario = Horarios.IdHorario
    WHERE Fecha BETWEEN @fechaini AND @fechafin
      AND (@person = '0' OR ResumenAsistencia.Person = @person)
    ORDER BY SY_Person.Name,
             Fecha;
END;
GO
