SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[sp_ca_listajustificaciones_web]
@cia char(4), @person varchar(20)
as
begin 
    select 
        SY_Person.person as DNI, SY_Person.Name, CA_TipoJustificacion.Abreviatura, CA_JustificacionPersona.fechainicio, CA_JustificacionPersona.fechafin,
        CA_JustificacionPersona.comentario, CA_JustificacionPersona.id as ID, CA_JustificacionPersona.idjustificacion as idjustificacion
    from CA_JustificacionPersona inner join SY_Person on (CA_JustificacionPersona.person = SY_Person.Person)
    inner join CA_TipoJustificacion on (CA_JustificacionPersona.idjustificacion = CA_TipoJustificacion.IdJustificacion)
    WHERE CA_JustificacionPersona.company = @cia
    and (@person = '0' or CA_JustificacionPersona.person = @person)
    order by 2, 4
end
