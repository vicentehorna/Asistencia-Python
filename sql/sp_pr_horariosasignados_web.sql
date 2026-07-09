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
