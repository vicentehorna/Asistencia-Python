/*
  Columnas GPS de dbo.RegistroAsistencia — SOLO hm_quimica.
  Las guarda el aplicativo de marcación (Latitud/Longitud DECIMAL(10,7), PC = equipo).
  sp_pr_listadomarcas_web las lee con SQL dinámico solo en hm_quimica;
  en cualquier otra BD devuelve NULL y la pantalla muestra "Sin GPS".
*/
SET ANSI_NULLS ON;
GO
IF DB_NAME() = N'hm_quimica' AND COL_LENGTH('dbo.RegistroAsistencia', 'Latitud') IS NULL
    ALTER TABLE [dbo].[RegistroAsistencia] ADD [Latitud] DECIMAL(10, 7) NULL;
GO
IF DB_NAME() = N'hm_quimica' AND COL_LENGTH('dbo.RegistroAsistencia', 'Longitud') IS NULL
    ALTER TABLE [dbo].[RegistroAsistencia] ADD [Longitud] DECIMAL(10, 7) NULL;
GO
IF DB_NAME() = N'hm_quimica' AND COL_LENGTH('dbo.RegistroAsistencia', 'PC') IS NULL
    ALTER TABLE [dbo].[RegistroAsistencia] ADD [PC] VARCHAR(255) NULL;
GO
