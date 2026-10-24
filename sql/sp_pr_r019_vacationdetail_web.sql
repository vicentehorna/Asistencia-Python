

CREATE OR ALTER PROCEDURE [dbo].[sp_pr_r019_vacationdetail_web]
(
    @cia VARCHAR(20),
    @period varchar(20), 
    @person varchar(20),
    @dni varchar(20)
   
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
            vd.prperiod,
            e.person AS person,
            LTRIM(RTRIM(
                ISNULL(sp.lastname1, '') + ' ' + 
                ISNULL(sp.lastname2, '') + ' ' + 
                ISNULL(sp.name1, '') + ' ' + 
                ISNULL(sp.name2, '')
            )) AS name,
            vd.datebegin,
            vd.dateend,
            vd.days,
            
           
            v.controlyear,
            sp.documentnumber,
            pos.Description AS cargo
        FROM pr_vacationdetail vd 
        INNER JOIN PR_Vacation v (nolock) ON vd.person = v.Person AND vd.Company = v.Company AND vd.line = v.line
        INNER JOIN PR_Employee e (nolock) ON vd.Person = e.Person AND vd.Company = e.Company
        INNER JOIN SY_Person sp (nolock) ON vd.Person = sp.Person AND e.Person = sp.Person
        INNER JOIN pr_payrolltype pt (nolock) ON e.PayRollType = pt.PayRollType
        LEFT JOIN pr_position pos (nolock) ON e.position = pos.position
        WHERE vd.company = @cia
          
          AND (@person = '0' OR e.person = @person)
          AND ((@period = '0') OR (left(vd.prperiod,6) = left(@period,6))) 
          and (@dni = '' or sp.Person like '%' + @dni  + '%')
          and e.Status = 'N'
         -- AND (@par_repunit_all = 'Y' OR sp.Replicationunit = @par_repunit)
          --AND (@par_year_all = 'Y' OR v.controlyear = @par_year)
          --AND (@par_status = 'N' OR (@par_status = 'Y' AND e.status = 'N'))
          /* Filtro de Jefatura Comentado Originalmente */
        ORDER BY 3;
   
    
END
GO
