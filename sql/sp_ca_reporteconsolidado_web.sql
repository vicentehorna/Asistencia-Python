SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_ca_reporteconsolidado_web]
    @cia char(4),
    @person varchar(20),
    @fechaini datetime,
    @fechafin datetime
AS
BEGIN
    SET NOCOUNT ON;
    Select  
        ResumenAsistencia.person, SY_Person.Name, sum(minutostarde) AS tardanza, sum(case when falta = 'Y' then 1 else 0 end) as faltas, sum(MinutosAdicionales) as Adicional
    from ResumenAsistencia INNER JOIN SY_Person on (ResumenAsistencia.person = SY_Person.Person)
    where ResumenAsistencia.company = @cia 
    AND (@person = '0' or ResumenAsistencia.person = @person) 
    AND Fecha BETWEEN CONVERT(date, @fechaini) AND CONVERT(date, @fechafin)
    group by ResumenAsistencia.person, SY_Person.Name
    order by 2
END
