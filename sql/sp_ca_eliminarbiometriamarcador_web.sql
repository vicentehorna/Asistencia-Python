/*
  Procedimiento: sp_ca_eliminarbiometriamarcador_web
  Uso: Seguridad > Acceso al Marcador (DELETE /api/seguridad/acceso-marcador/biometria)
  Parámetros: @cia, @person, @usuario
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_ca_eliminarbiometriamarcador_web]
    @cia     VARCHAR(4),
    @person  VARCHAR(20),
    @usuario VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM PR_Employee
        WHERE Person = @person
          AND Company = @cia
          AND Status = 'N'
    )
    BEGIN
        RAISERROR('Trabajador no activo en la compañía indicada.', 16, 1);
        RETURN;
    END;

    DELETE FROM SY_Person_biometry
    WHERE Person = @person;
END;
GO
