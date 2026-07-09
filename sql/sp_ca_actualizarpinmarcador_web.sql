/*
  Procedimiento: sp_ca_actualizarpinmarcador_web
  Uso: Seguridad > Acceso al Marcador (POST /api/seguridad/acceso-marcador/pin)
  Parámetros: @cia, @person, @pin, @usuario
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_ca_actualizarpinmarcador_web]
    @cia     VARCHAR(4),
    @person  VARCHAR(20),
    @pin     VARCHAR(10),
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

    IF LTRIM(RTRIM(ISNULL(@pin, ''))) = ''
    BEGIN
        RAISERROR('El PIN no puede estar vacío.', 16, 1);
        RETURN;
    END;

    IF LEN(LTRIM(RTRIM(@pin))) <> 4
       OR PATINDEX('%[^0-9]%', LTRIM(RTRIM(@pin))) > 0
    BEGIN
        RAISERROR('El PIN debe tener exactamente 4 números.', 16, 1);
        RETURN;
    END;

    UPDATE SY_Person
    SET pinAcceso = LTRIM(RTRIM(@pin))
    WHERE Person = @person;
END;
GO
