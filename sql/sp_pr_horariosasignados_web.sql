SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[sp_pr_horariosasignados_web]
@cia varchar(4)
as 
Begin
    select 
        SY_Person.Person as person,
        SY_Person.Name as name,
        Horarios.NombreHorario,
        AsignacionHorarios.FechaInicio as fechinicio,
        AsignacionHorarios.FechaFin as fechafin, AsignacionHorarios.IdAsignacion
    from AsignacionHorarios inner join Horarios on (AsignacionHorarios.IdHorario = Horarios.IdHorario and AsignacionHorarios.Company = @cia)
    inner join SY_Person on (AsignacionHorarios.Person = SY_Person.Person)
    order by 2
End
