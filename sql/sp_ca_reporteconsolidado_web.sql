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
