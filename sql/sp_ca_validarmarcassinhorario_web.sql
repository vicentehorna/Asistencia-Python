/*
  Procedimiento: sp_ca_validarmarcassinhorario_web
  Uso: Procesar Asistencia — advertencias al consultar (marcas sin horario asignado)
  Parámetros: @cia, @fechaini, @fechafin
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_ca_validarmarcassinhorario_web]
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
