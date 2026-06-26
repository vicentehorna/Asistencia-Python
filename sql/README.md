# Procedimientos almacenados — Asistencia

Un archivo `.sql` por cada SP referenciado en `app.py` / `database.py`.

## Tablas (`tables/`)

| Script | Descripción |
|--------|-------------|
| `tables/RegistroAsistencia.sql` | Marcaciones (manual y biométrico); FK a `Trabajadores` |

## Procedimientos

| Procedimiento | Origen | Parámetros | Estado |
|---------------|--------|------------|--------|
| `sp_ca_listajustificaciones_web` | app.py | @cia, @person | exportado desde BD |
| `sp_ca_procesarasistencia_web` | app.py, database.py | @cia, @person, @fechaini, @fechafin | definición en repo |
| `sp_ca_reporteconsolidado_web` | app.py | @cia, @person, @fechaini, @fechafin | exportado desde BD |
| `sp_ca_ReporteResumenAsistencia_web` | app.py | @cia, @fechaini, @fechafin, @person | definición en repo |
| `sp_pr_Actualizardescarga_web` | database.py | @cia, @person, @tipodocumento, @prperiod | marcador (no en BD actual) |
| `sp_pr_AprobarSolicitud_web` | database.py | @cia, @person, @controlyear, @line, @userid | marcador (no en BD actual) |
| `sp_pr_AprobarSolicitudesPendientes_web` | database.py | @cia, @name, @estado | marcador (no en BD actual) |
| `sp_pr_ausenciasperson_web` | database.py | @cia, @person | marcador (no en BD actual) |
| `sp_pr_CambiarPassword_web` | database.py | @userid, @clave_ant, @clave_nueva | marcador (no en BD actual) |
| `sp_pr_constanciatrabajo_web` | database.py | @person, @cia | marcador (no en BD actual) |
| `sp_pr_datosusuario_web` | database.py | @userid | marcador (no en BD actual) |
| `sp_pr_detalleboletaaportes_web` | database.py | @cia, @process, @payrolltype, @period, @person | marcador (no en BD actual) |
| `sp_pr_detalleboletadescuentos_web` | database.py | @cia, @process, @payrolltype, @period, @person | marcador (no en BD actual) |
| `sp_pr_detalleboletaingresos_web` | database.py | @cia, @process, @payrolltype, @period, @person | marcador (no en BD actual) |
| `sp_pr_EliminarSolicitudPermiso_web` | database.py | @cia, @person, @line | marcador (no en BD actual) |
| `sp_pr_enviocomprobantes_web` | database.py | @cia, @tipodoc, @prperiod | marcador (no en BD actual) |
| `sp_pr_FiltroPeriodos_web` | database.py | @cia | marcador (no en BD actual) |
| `sp_pr_generarboleta_web` | database.py | @cia, @process, @payrolltype, @period, @person | marcador (no en BD actual) |
| `sp_pr_horariosasignados_web` | app.py | @cia | exportado desde BD |
| `sp_pr_listadocumentos_web` | database.py | @cia, @person, @tipodoc | marcador (no en BD actual) |
| `sp_pr_listadogenerarboletas_web` | database.py | @cia, @payrolltype, @processtype, @period, @name | marcador (no en BD actual) |
| `sp_pr_listadomarcas_web` | database.py | @cia, @Fechainicio, @FechaFin, @person | definición en repo |
| `sp_pr_listaenvioalertas_web` | database.py | @cia | exportado desde BD |
| `sp_pr_ListarSolicitudPermiso_web` | database.py | @cia, @person | marcador (no en BD actual) |
| `sp_pr_registrarcomprobantes_web` | database.py | @cia, @payrolltype, @processtype, @period, @person, @userid, @filename, @tipo | marcador (no en BD actual) |
| `sp_pr_RegistrarSolicitudPermiso_web` | database.py | @cia, @person, @userid, @controlyear, @fechaini, @fechaFin, @comentario | marcador (no en BD actual) |
| `sp_pr_reportedescargas_web` | database.py | @cia, @tipodoc, @prperiod | marcador (no en BD actual) |
| `sp_pr_reporteplame_total_web` | app.py | @cia, @payrolltype, @period, @person | marcador (no en BD actual) |
| `sp_pr_reporteplamevertical_web` | app.py | @cia, @payrolltype, @process, @period, @person | marcador (no en BD actual) |
| `SP_PR_ReportePromedioLiquidacion` | app.py | @cia, @payrolltype, @period, @person | marcador (no en BD actual) |
| `sp_pr_selectorcompanias_web` | app.py, database.py | (sin parámetros) | definición en repo |
| `sp_pr_selectorperiodos_web` | app.py, database.py | @cia, @payrolltype, @processtype | marcador (no en BD actual) |
| `sp_pr_selectorpersonas_web` | app.py | @cia | definición en repo |
| `sp_pr_selectorpersonasCA_web` | app.py | @cia, @fechaini, @fechafin | definición en repo |
| `sp_pr_selectorplanillas_web` | app.py, database.py | @cia | marcador (no en BD actual) |
| `sp_pr_selectorprocesos_web` | app.py, database.py | @cia, @payrolltype | marcador (no en BD actual) |
| `sp_pr_selectortipojus_web` | app.py | (sin parámetros) | exportado desde BD |
| `sp_pr_vacacionesperson_web` | database.py | @cia, @person | marcador (no en BD actual) |
