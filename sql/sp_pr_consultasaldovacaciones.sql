/*
  SP: sp_pr_consultasaldovacaciones
  Origen: hm_safari (PortalMinero / Solicitud de Vacaciones)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/*
declare @fecha datetime
set @fecha = convert(datetime, '20260602')
execute sp_pr_consultasaldovacaciones  'SB06', @fecha ,'75164468'
*/
--select * from xx_saldovacaciones

CREATE OR ALTER PROCEDURE [dbo].[sp_pr_consultasaldovacaciones]
@company char(4),  @date datetime,  @person varchar(20), @controlyear varchar(4)
as
begin
	declare @year numeric(9,0), @actualyear numeric(9,0), @consumo numeric(9,4), @faltas integer, @licencias integer, @descansos integer
	declare @documentnumber varchar(20), @name varchar(255), @fecha varchar(20)
	declare @inicio datetime,@inicioProvision datetime, @finProvision datetime

	update PR_Vacation set consumeddays2 = consumeddays 
	

	update PR_Vacation set consumeddays2 = consumeddays2 - (select sum(Days) from PR_VacationDetail where Person = PR_Vacation.Person and line = PR_Vacation.line and Company = PR_Vacation.Company and Datebegin > @date) where
	exists (select * from PR_VacationDetail where Person = PR_Vacation.Person and line = PR_Vacation.line and Company = PR_Vacation.Company and Datebegin > @date)

	set @descansos = 0

	delete from xx_saldovacaciones

	set @year = year(@date) + 1

	insert into xx_saldovacaciones (company,person,name,entrydate,payrolltype)
	select distinct compania,DocumentNumber,Name,CONVERT(varchar(8), entrydate,112) as fechaingreso,
	PayRollType		
	from (
	select 
	@company as compania,
	SY_Person.Person as DocumentNumber ,SY_Person.Name,isnull(pr_employee.reentrydate,pr_employee.entrydate) as entrydate,
	ControlYear,
	--case when CONVERT(varchar(8), DateBeginRights,112) <= CONVERT(varchar(8), @date,112) then abs(consumeddays - acquireddays) else 0 end as porconsumir,
	case when CONVERT(varchar(8), DateBeginProvision,112) <= CONVERT(varchar(8), @date,112) then
		case when CONVERT(varchar(8), DateBeginRights,112) <= CONVERT(varchar(8), @date,112) then
			abs(consumeddays2 - acquireddays)
		else
			round((dbo.f_getDias360(DateBeginProvision,@date)*2.5)/30,2) - consumeddays2
		end
	else
		0--round((dbo.f_getDias360(@date,DateBeginProvision)*2.5)/30,2) - ConsumedDays
	end  as porconsumir,
	PR_Employee.PayRollType as PayRollType
	from PR_Vacation inner join PR_Employee on (PR_Vacation.Person = PR_Employee.Person
	and PR_Employee.Status = 'N') inner join SY_Person on (PR_Employee.Person = SY_Person.Person)
	inner join SY_Company on (PR_Vacation.Company = SY_Company.Company)
	where ControlYear < year(@date) + 1
	and ControlYear >= year(isnull(reentrydate,EntryDate))
	--and CONVERT(varchar(8), DateBeginRights,112) <= CONVERT(varchar(8), @date,112)
	--and (@payrolltype_all = 'Y' or PR_Employee.PayRollType = @payrolltype)
	and ( PR_Vacation.Person = @person)
	--and (@cesados = 'T' or ((@cesados = 'Y' and PR_Employee.CeaseDate is not null) or (@cesados = 'N' and PR_Employee.CeaseDate is null))) 
	and PR_Vacation.Company = @company
	and abs(consumeddays2 - acquireddays) > 0)X
	--where DocumentNumber = '45129262'
	order by 1,3

	--select * from xx_saldovacaciones
	Declare Vacaciones Cursor For
	select DocumentNumber,Name,CONVERT(varchar(8), entrydate,112) as fechaingreso,
	controlyear, porconsumir as porconsumir, X.inicioProvision, X.finProvision
	from (
	select 
	SY_Company.Description as compania,
	SY_Person.person as DocumentNumber,SY_Person.Name,isnull(pr_employee.reentrydate,pr_employee.entrydate) as entrydate,
	ControlYear,
	--case when CONVERT(varchar(8), DateBeginRights,112) <= CONVERT(varchar(8), @date,112) then abs(consumeddays - acquireddays) else 0 end as porconsumir
	-- abs(consumeddays - acquireddays) as porconsumir
	case when CONVERT(varchar(8), DateBeginProvision,112) <= CONVERT(varchar(8), @date,112) then
		case when CONVERT(varchar(8), DateBeginRights,112) <= CONVERT(varchar(8), @date,112) then
			abs(consumeddays2 - acquireddays)
		else
			round((dbo.f_getDias360(DateBeginProvision,@date)*2.5)/30,2) - consumeddays2
		end
	else
		0--round((dbo.f_getDias360(@date,DateBeginProvision)*2.5)/30,2) - ConsumedDays
	end  as porconsumir,
	PR_Vacation.DateBeginProvision as inicioProvision,
	PR_Vacation.DateBeginRights as finProvision
	from PR_Vacation inner join PR_Employee on (PR_Vacation.Person = PR_Employee.Person
	and PR_Employee.Status = 'N') inner join SY_Person on (PR_Employee.Person = SY_Person.Person)
	inner join SY_Company on (PR_Vacation.Company = SY_Company.Company)
	where ControlYear < year(@date) + 1
	and ControlYear >= year(isnull(reentrydate,EntryDate))
	--and (@payrolltype_all = 'Y' or PR_Employee.PayRollType = @payrolltype)
	and PR_Vacation.Company = @company
	--and CONVERT(varchar(8), DateBeginRights,112) <= CONVERT(varchar(8), @date,112)
	and ( PR_Vacation.Person = @person)
	--and (@cesados = 'T' or ((@cesados = 'Y' and PR_Employee.CeaseDate is not null) or (@cesados = 'N' and PR_Employee.CeaseDate is null))) 
	and abs(consumeddays2 - acquireddays) > 0)X
	--where DocumentNumber = '45129262'
	order by 2

	
		OPEN Vacaciones 
		FETCH NEXT FROM Vacaciones INTO   @documentnumber, @name,@fecha,@actualyear,@consumo, @inicioProvision,@finProvision
		WHILE @@FETCH_STATUS = 0 
		BEGIN 
			--print 'aca'
			if @actualyear = @year - 5
				update xx_saldovacaciones set saldo1 = @consumo where person = @documentnumber

			if @actualyear = @year - 4
				update xx_saldovacaciones set saldo2 = @consumo where person = @documentnumber

			if @actualyear = @year - 3
				update xx_saldovacaciones set saldo3 = @consumo where person = @documentnumber

			if @actualyear = @year - 2
				update xx_saldovacaciones set saldo4 = @consumo where person = @documentnumber

			if @actualyear = @year - 1
				update xx_saldovacaciones set saldo5 = @consumo where person = @documentnumber
			--update xx_saldovacaciones set 
			--	saldo1 = case when @actualyear = @year - 5 then @consumo else 0 end,
			--	saldo2 = case when @actualyear = @year - 4 then @consumo else 0 end,
			--	saldo3 = case when @actualyear = @year - 3 then @consumo else 0 end,
			--	saldo4 = case when @actualyear = @year - 2 then @consumo else 0 end,
			--	saldo5 = case when @actualyear = @year - 1 then @consumo else 0 end
			--where person = @documentnumber

			set @faltas = 0

			set @inicio = @fecha
			while(@inicio < @date)
			begin
				set @faltas = @faltas  + case when isnull((select count(*) from PR_EmployeeMedicalRest inner join PR_MedicalRestType on (PR_EmployeeMedicalRest.MedicalRestType = PR_MedicalRestType.MedicalRestType AND PR_MedicalRestType.pdt = '07')
				where PR_EmployeeMedicalRest.Person = @documentnumber and PR_EmployeeMedicalRest.Company = @company
				and @inicio between PR_EmployeeMedicalRest.DateBegin and PR_EmployeeMedicalRest.DateEnd),0) > 0 then  1
				else 0 end

				set @inicio = dateadd( dd,1 ,@inicio)
			end
			
			update xx_saldovacaciones set faltas = @faltas where person = @documentnumber

			set @licencias = 0

			set @inicio = @fecha
			while(@inicio <= @date)
			begin
				set @licencias = @licencias  + case when isnull((select count(*) from PR_EmployeeMedicalRest inner join PR_MedicalRestType on (PR_EmployeeMedicalRest.MedicalRestType = PR_MedicalRestType.MedicalRestType AND PR_MedicalRestType.pdt = '05')
				where PR_EmployeeMedicalRest.Person = @documentnumber and PR_EmployeeMedicalRest.Company = @company
				and @inicio between PR_EmployeeMedicalRest.DateBegin and PR_EmployeeMedicalRest.DateEnd),0) > 0 then  1
				else 0 end

				set @inicio = dateadd( dd,1 ,@inicio)
			end

			update xx_saldovacaciones set licencias = @licencias where person = @documentnumber

			set @descansos = 0

			set @inicio = @inicioProvision
			while(@inicio < @finProvision)
			begin
				--print @inicio
				set @descansos = @descansos  + case when isnull((select count(*) from PR_EmployeeMedicalRest inner join PR_MedicalRestType on (PR_EmployeeMedicalRest.MedicalRestType = PR_MedicalRestType.MedicalRestType AND PR_MedicalRestType.pdt = '20')
				where PR_EmployeeMedicalRest.Person = @documentnumber and PR_EmployeeMedicalRest.Company = @company
				and @inicio between PR_EmployeeMedicalRest.DateBegin and PR_EmployeeMedicalRest.DateEnd),0) > 0 then  1
				else 0 end
				--print convert(varchar(20), @descansos)
				
				set @inicio = dateadd( dd,1 ,@inicio)
			end

			update xx_saldovacaciones set descansos = isnull(descansos,0) + @descansos where person = @documentnumber

			
			

		FETCH NEXT FROM Vacaciones
	
		INTO  @documentnumber, @name,@fecha,@actualyear,@consumo,@inicioProvision,@finProvision
		END 
		
		CLOSE Vacaciones
		DEALLOCATE Vacaciones

		

	select 
		case when  year(@date) = @controlyear then isnull(saldo5,0) else
			case when  year(@date) - 1  = @controlyear then isnull(saldo4,0) else
				case when  year(@date) - 2 = @controlyear then isnull(saldo3,0) else
					case when  year(@date) - 3 = @controlyear then isnull(saldo2,0) else
						case when  year(@date) - 4 = @controlyear then isnull(saldo1,0) else 0  end end end end end as saldo
			
	from xx_saldovacaciones

end
GO
