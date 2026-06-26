SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[sp_pr_listaenvioalertas_web]
@cia varchar(4)
as
begin
    select 
        SY_Person.Person, SY_Person.Name, SY_Person.EMail, recibealertas
    from CA_ConfiguracionAlertas inner join SY_Person on 
    (CA_ConfiguracionAlertas.person = SY_Person.Person and CA_ConfiguracionAlertas.company = @cia)
    order by 2
end
