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
