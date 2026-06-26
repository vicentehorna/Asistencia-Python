/*
  Procedimiento: sp_pr_listaenvioalertas_web
  Uso: Configurar Alertas (GET /api/alertas/lista)
  Parámetros: @cia
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_pr_listaenvioalertas_web]
    @cia VARCHAR(4)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SY_Person.Person,
        SY_Person.Name,
        SY_Person.EMail,
        CA_ConfiguracionAlertas.RecibeAlertas AS recibealertas
    FROM CA_ConfiguracionAlertas
    INNER JOIN SY_Person
        ON CA_ConfiguracionAlertas.Person = SY_Person.Person
    WHERE CA_ConfiguracionAlertas.Company = @cia
    ORDER BY
        SY_Person.Name;
END
GO
