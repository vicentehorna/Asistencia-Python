/*
  Procedimiento: sp_ca_listajustificaciones_web
  Uso: Justificaciones por Persona (api/justificaciones_persona/listar)
  Parámetros: @cia, @person ('0' = todos los trabajadores)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_ca_listajustificaciones_web]
    @cia    CHAR(4),
    @person VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        P.Person AS DNI,
        P.Name,
        TJ.Abreviatura,
        JP.FechaInicio,
        JP.FechaFin,
        JP.Comentario,
        JP.Id AS ID,
        JP.IdJustificacion AS idjustificacion
    FROM CA_JustificacionPersona JP
    INNER JOIN SY_Person P
        ON JP.Person = P.Person
    INNER JOIN CA_TipoJustificacion TJ
        ON JP.IdJustificacion = TJ.IdJustificacion
    WHERE JP.company = @cia
      AND (@person = '0' OR JP.Person = @person)
    ORDER BY
        P.Name,
        JP.FechaInicio;
END
GO
