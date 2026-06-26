SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

create procedure [dbo].[sp_pr_selectortipojus_web]
as
begin
    select idjustificacion, descripcion, abreviatura from ca_tipojustificacion
end
