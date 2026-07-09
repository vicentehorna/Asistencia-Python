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
