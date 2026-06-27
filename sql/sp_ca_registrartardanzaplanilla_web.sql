/*
  Procedimiento: sp_ca_registrartardanzaplanilla_web
  Uso: Consolidado de Asistencia — Registro Planillas (MIN_TARDANZA en PR_EmployeeConcept)
  Parámetros: @cia, @prperiod, @person, @minutos, @xlastuser
  Retorna: Person, Name, Accion (I=insertado, U=actualizado, E=error), Mensaje
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_ca_registrartardanzaplanilla_web]
    @cia       VARCHAR(10),
    @prperiod  VARCHAR(10),
    @person    VARCHAR(20),
    @minutos   INT,
    @xlastuser VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @concept         VARCHAR(20);
    DECLARE @payrolltype     VARCHAR(20);
    DECLARE @costcenter      VARCHAR(20);
    DECLARE @costcentercode  VARCHAR(20);
    DECLARE @nombre          VARCHAR(100);
    DECLARE @replicationunit VARCHAR(4);
    DECLARE @periodo         VARCHAR(10);
    DECLARE @accion          CHAR(1) = 'E';
    DECLARE @mensaje         VARCHAR(500) = '';

    SET @cia = LTRIM(RTRIM(ISNULL(@cia, '')));
    SET @person = LTRIM(RTRIM(ISNULL(@person, '')));
    SET @periodo = REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(@prperiod, ''))), '-', ''), '/', '');
    IF LEN(@periodo) >= 8 AND ISNUMERIC(LEFT(@periodo, 8)) = 1
        SET @periodo = LEFT(@periodo, 8);
    SET @xlastuser = NULLIF(LTRIM(RTRIM(ISNULL(@xlastuser, ''))), '');
    SET @minutos = ISNULL(@minutos, 0);

    IF @cia = ''
    BEGIN
        SET @mensaje = 'Compañía no válida.';
        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    IF @periodo = ''
    BEGIN
        SET @mensaje = 'Periodo de planilla no válido.';
        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    IF @person = ''
    BEGIN
        SET @mensaje = 'Trabajador no válido.';
        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    IF @minutos < 0
    BEGIN
        SET @mensaje = 'Los minutos de tardanza no pueden ser negativos.';
        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    SELECT TOP 1 @concept = LTRIM(RTRIM(c.Concept))
    FROM PR_Concept c
    WHERE c.Company = @cia
      AND c.FormulaCode = 'MIN_TARDANZA'
      AND c.Status = 'A';

    IF @concept IS NULL OR @concept = ''
    BEGIN
        SET @mensaje = 'No existe concepto activo MIN_TARDANZA para la compañía.';
        SELECT @person AS Person, '' AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    SELECT
        @payrolltype = LTRIM(RTRIM(e.PayRollType)),
        @costcenter = ISNULL(NULLIF(LTRIM(RTRIM(e.CostCenter)), ''), ''),
        @costcentercode = ISNULL(
            NULLIF(LTRIM(RTRIM(e.CostCenterName)), ''),
            ISNULL(NULLIF(LTRIM(RTRIM(e.CostCenter)), ''), '')
        ),
        @nombre = LTRIM(RTRIM(sp.Name)),
        @replicationunit = NULLIF(LTRIM(RTRIM(sp.ReplicationUnit)), '')
    FROM PR_Employee e
    INNER JOIN SY_Person sp ON sp.Person = e.Person
    WHERE e.Company = @cia
      AND e.Person = @person
      AND e.Status = 'N';

    IF @payrolltype IS NULL
    BEGIN
        SET @mensaje = 'Trabajador no activo en la compañía.';
        SELECT @person AS Person, ISNULL(@nombre, '') AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    IF @payrolltype = ''
    BEGIN
        SET @mensaje = 'El trabajador no tiene tipo de planilla.';
        SELECT @person AS Person, @nombre AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM PR_Period p
        WHERE p.Company = @cia
          AND p.PayRollType = @payrolltype
          AND p.PRPeriod = @periodo
    )
    BEGIN
        SET @mensaje = 'El periodo ' + @periodo + ' no existe para el tipo de planilla del trabajador.';
        SELECT @person AS Person, @nombre AS Name, @accion AS Accion, @mensaje AS Mensaje;
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM PR_EmployeeConcept ec
        WHERE ec.Person = @person
          AND ec.Company = @cia
          AND ec.Concept = @concept
          AND ec.PayRollType = @payrolltype
          AND ec.PRPeriodStart = @periodo
          AND ec.CostCenter = @costcenter
    )
    BEGIN
        UPDATE PR_EmployeeConcept
        SET PRPeriodEnd = @periodo,
            ConceptValue = @minutos,
            ConceptCurrency = 'LO',
            ConceptValueLo = @minutos,
            ConceptValueEx = 0,
            ExchangeRate = 0,
            FlagApplyFormula = 'N',
            FlagFrecuencyType = 'T',
            Application = 'PR',
            PercentageDistribution = 'A',
            XLastUser = @xlastuser,
            XLastDate = GETDATE()
        WHERE Person = @person
          AND Company = @cia
          AND Concept = @concept
          AND PayRollType = @payrolltype
          AND PRPeriodStart = @periodo
          AND CostCenter = @costcenter;

        SET @accion = 'U';
        SET @mensaje = '';
    END
    ELSE
    BEGIN
        INSERT INTO PR_EmployeeConcept (
            Person, Company, Concept, PayRollType, PRPeriodStart, CostCenter,
            PRPeriodEnd, ConceptValue, Application, ConceptCurrency, Comments,
            FlagApplyFormula, FlagFrecuencyType, ReplicationUnit,
            XLastUser, XLastDate, ConceptValueLo, ConceptValueEx, ExchangeRate,
            CostCenterCode, Project, ProjectCode, PercentageDistribution, FlagCopy
        )
        VALUES (
            @person, @cia, @concept, @payrolltype, @periodo, @costcenter,
            @periodo, @minutos, 'PR', 'LO', NULL,
            'N', 'T', @replicationunit,
            @xlastuser, GETDATE(), @minutos, 0, 0,
            @costcentercode, '', '', 'A', NULL
        );

        SET @accion = 'I';
        SET @mensaje = '';
    END

    SELECT @person AS Person, @nombre AS Name, @accion AS Accion, @mensaje AS Mensaje;
END
GO
