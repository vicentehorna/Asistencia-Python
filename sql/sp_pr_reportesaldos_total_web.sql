


--select * from SY_Company

--sp_pr_reportesaldos_total 'SB05', 'Y', '', '20221231', 'Y', '74282209', 'T'

	--Select ControlYear, ConsumedDays, line, DateBeginProvision, dbo.f_getDias360(DateBeginProvision,'20220211')   from PR_Vacation where Company = 'BGT' and Person = '43667171'
	--	order by 1




CREATE OR ALTER PROCEDURE [dbo].[sp_pr_reportesaldos_total_web]
@company char(4),     @person varchar(20), @date datetime, @cesados char(1), @dni varchar(20)
as
begin

	declare @fecha_hoy datetime

	declare @consumidos1 int
	set @consumidos1 = 0

	set @fecha_hoy = @date

	CREATE TABLE #temporal(
	[Codigo] [varchar] (20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,
	[Nombre] [varchar] (200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,
	[FechaIngreso] datetime NULL,
	[FechaCese] datetime NULL,
	[ControlYear] [varchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,
	[FechaInicio] datetime NULL,
	[FechaFin] datetime NULL,
	tomados int NULL,
	pendientes numeric(9,4) NULL,
	vencidos numeric(9,4) NULL,
	truncos varchar(10) NULL
	) ON [PRIMARY]

	IF @@ERROR <> 0
	BEGIN
		RETURN(1)	
	END

	declare @year varchar(10), @consumidos int, @line int
	declare @DateBeginProvision datetime, @fechacese datetime
	declare @person_id varchar(20), @nombre varchar(255)

	set @fechacese = NULL
	Declare vacaciones_general Cursor For
	Select  pr_employee.Person, SY_Person.Name, pr_employee.ceasedate  from PR_Employee inner join SY_Person on (PR_Employee.Person = SY_Person.Person) where PR_Employee.status = 'N'
--	and ( PR_Employee.PayRollType = @payrolltype)
	and (@person = '0' or PR_Employee.Person = @person)
	and (@cesados = 'T' or ((@cesados = 'Y' and PR_Employee.CeaseDate is not null) or (@cesados = 'N' and PR_Employee.CeaseDate is null))) 
	 and (@dni = '' or SY_Person.Person like '%' + @dni  + '%')
	and PR_Employee.Company = @company
	--and PR_Employee.Person in ('41727448', '20115135', '41854125')
	order by 2
	
		OPEN vacaciones_general 
		FETCH NEXT FROM vacaciones_general INTO  @person_id, @nombre, @fechacese
		WHILE @@FETCH_STATUS = 0 
		BEGIN 

		SET @consumidos = 0
		SET @DateBeginProvision = NULL
		if @fechacese is not null and @fechacese < @date
		begin 
			set @date = @fechacese
		end
		else
		begin
			set @date = @fecha_hoy
		end
		declare @valor numeric(19,4)
		declare @fecha_ref datetime
		Declare vacaciones Cursor For
		Select ControlYear, ConsumedDays, line, DateBeginProvision  from PR_Vacation where Company = @company and Person = @person_id
		order by 1

			OPEN vacaciones 
			FETCH NEXT FROM vacaciones INTO  @year, @consumidos, @line, @DateBeginProvision
			WHILE @@FETCH_STATUS = 0 
			BEGIN 
			--recorro cada periodo anual, registro los tomados si hay dias consumidos o evaluo pendietes o vencidos 	
				if @consumidos > 0
				begin
					SET @consumidos1 = isnull((SELECT sum(Days) from PR_VacationDetail where Company = @company AND Person = @person_id and line = @line AND convert(varchar(8), Dateend,112) <= convert(varchar(8),@date,112)),0)

					insert into #temporal
					select PR_VacationDetail.Person, SY_Person.Name, isnull(ReEntryDate,EntryDate), pr_employee.ceasedate, @year, Datebegin, Dateend, 
					--isnull((SELECT sum(Days) from PR_VacationDetail where Company = @company AND Person = @person_id and line = @line AND convert(varchar(8), Dateend,112) <= convert(varchar(8),@date,112)),0) as days,
					 days,
					0,0,''  from PR_VacationDetail inner join SY_Person on (PR_VacationDetail.Person = SY_Person.Person) 
					inner  join PR_Employee on (PR_VacationDetail.Person = PR_Employee.Person and PR_Employee.Company = @company)
					where 
					pr_vacationdetail.Company = @company and pr_vacationdetail.Person = @person_id and line = @line
					
				
					update #temporal set pendientes = case when dbo.f_getDias360(@DateBeginProvision,@date) < 720 
					and dbo.f_getDias360(@DateBeginProvision,@date) >= 360 then 30 - @consumidos else 
					case when dbo.f_getDias360(@DateBeginProvision,@date) < 360 then round((dbo.f_getDias360(@DateBeginProvision,@date)*2.5)/30,2) - @consumidos else 0 end end,
					vencidos = case when dbo.f_getDias360(@DateBeginProvision,@date) >= 720 then 30 - @consumidos else 0 end
					where ControlYear = @year and Codigo = @person_id and FechaInicio = (select max(Datebegin) from PR_VacationDetail where Company = @company and Person = @person_id and line = @line )
					
				end
			
				if @consumidos = 0
				begin
					if dbo.f_getDias360(@DateBeginProvision,@date) < 360 and dbo.f_getDias360(@DateBeginProvision,@date) > 0
					begin
						--IF @person_id = '03692233' print @DateBeginProvision

						--select @valor = round((dbo.f_getDias360(DateBeginProvision,@date)*2.5)/30,2)  from 
						--PR_Vacation inner join SY_Person on (PR_Vacation.Person = SY_Person.Person) 
						--inner  join PR_Employee on (PR_Vacation.Person = PR_Employee.Person and PR_Employee.Company = @company)
						--where 
						--PR_Vacation.Company = @company and PR_Vacation.Person = @person_id and line = @line

						--select @fecha_ref = DateBeginProvision  from 
						--PR_Vacation inner join SY_Person on (PR_Vacation.Person = SY_Person.Person) 
						--inner  join PR_Employee on (PR_Vacation.Person = PR_Employee.Person and PR_Employee.Company = @company)
						--where 
						--PR_Vacation.Company = @company and PR_Vacation.Person = @person_id and line = @line

						--print convert(varchar(20),@valor)
						--print convert(varchar(50),@date)

						insert into #temporal
						select PR_Vacation.Person, SY_Person.Name, isnull(ReEntryDate,EntryDate), pr_employee.ceasedate, @year, 
						NULL, NUll, 0,round((dbo.f_getDias360(DateBeginProvision,@date)*2.5)/30,2),0,'x'  from 
						PR_Vacation inner join SY_Person on (PR_Vacation.Person = SY_Person.Person) 
						inner  join PR_Employee on (PR_Vacation.Person = PR_Employee.Person and PR_Employee.Company = @company)
						where 
						PR_Vacation.Company = @company and PR_Vacation.Person = @person_id and line = @line
					end

					if dbo.f_getDias360(@DateBeginProvision,@date) <= 720 and dbo.f_getDias360(@DateBeginProvision,@date) >= 360
					begin
						insert into #temporal
						select PR_Vacation.Person, SY_Person.Name, isnull(ReEntryDate,EntryDate), pr_employee.ceasedate, @year, 
						NULL, NUll, 0,30,0,''  from 
						PR_Vacation inner join SY_Person on (PR_Vacation.Person = SY_Person.Person) 
						inner  join PR_Employee on (PR_Vacation.Person = PR_Employee.Person and PR_Employee.Company = @company)
						where 
						PR_Vacation.Company = @company and PR_Vacation.Person = @person_id and line = @line
					end

					if dbo.f_getDias360(@DateBeginProvision,@date) > 720 
					begin
						insert into #temporal
						select PR_Vacation.Person, SY_Person.Name, isnull(ReEntryDate,EntryDate), pr_employee.ceasedate, @year, 
						NULL, NUll, 0,0,30,''  from 
						PR_Vacation inner join SY_Person on (PR_Vacation.Person = SY_Person.Person) 
						inner  join PR_Employee on (PR_Vacation.Person = PR_Employee.Person and PR_Employee.Company = @company)
						where 
						PR_Vacation.Company = @company and PR_Vacation.Person = @person_id and line = @line
					end

				end


				--Select ControlYear, ConsumedDays, line,*  from PR_Vacation where Company = 'BGT' and Person = '71721563'

			FETCH NEXT FROM vacaciones	
			INTO  @year, @consumidos, @line, @DateBeginProvision
			END 
		
			CLOSE vacaciones
			DEALLOCATE vacaciones

			FETCH NEXT FROM vacaciones_general	
		INTO  @person_id, @nombre, @fechacese
		END 
		
		CLOSE vacaciones_general
		DEALLOCATE vacaciones_general

		delete from xx_saldo_vacaciones where company = @company

		insert into xx_saldo_vacaciones (company, person, tomados, pendientes, vencidos)
		select @company, Codigo, tomados, pendientes, vencidos from #temporal

		select * from #temporal
		order by 2,5,6

		

end
GO
