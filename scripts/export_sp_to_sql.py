"""Script temporal: exportar SP referenciados en el proyecto."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from database import DatabaseConfig

SP_USAGE = {
    "sp_ca_listajustificaciones_web": ("app.py", "@cia, @person"),
    "sp_ca_procesarasistencia_web": ("app.py, database.py", "@cia, @person, @fechaini, @fechafin"),
    "sp_ca_reporteconsolidado_web": ("app.py", "@cia, @person, @fechaini, @fechafin"),
    "sp_ca_ReporteResumenAsistencia_web": ("app.py", "@cia, @fechaini, @fechafin, @person"),
    "sp_pr_Actualizardescarga_web": ("database.py", "@cia, @person, @tipodocumento, @prperiod"),
    "sp_pr_AprobarSolicitud_web": ("database.py", "@cia, @person, @controlyear, @line, @userid"),
    "sp_pr_AprobarSolicitudesPendientes_web": ("database.py", "@cia, @name, @estado"),
    "sp_pr_ausenciasperson_web": ("database.py", "@cia, @person"),
    "sp_pr_CambiarPassword_web": ("database.py", "@userid, @clave_ant, @clave_nueva"),
    "sp_pr_constanciatrabajo_web": ("database.py", "@person, @cia"),
    "sp_pr_datosusuario_web": ("database.py", "@userid"),
    "sp_pr_detalleboletaaportes_web": ("database.py", "@cia, @process, @payrolltype, @period, @person"),
    "sp_pr_detalleboletadescuentos_web": ("database.py", "@cia, @process, @payrolltype, @period, @person"),
    "sp_pr_detalleboletaingresos_web": ("database.py", "@cia, @process, @payrolltype, @period, @person"),
    "sp_pr_EliminarSolicitudPermiso_web": ("database.py", "@cia, @person, @line"),
    "sp_pr_enviocomprobantes_web": ("database.py", "@cia, @tipodoc, @prperiod"),
    "sp_pr_FiltroPeriodos_web": ("database.py", "@cia"),
    "sp_pr_generarboleta_web": ("database.py", "@cia, @process, @payrolltype, @period, @person"),
    "sp_pr_horariosasignados_web": ("app.py", "@cia"),
    "sp_pr_listadocumentos_web": ("database.py", "@cia, @person, @tipodoc"),
    "sp_pr_listadogenerarboletas_web": ("database.py", "@cia, @payrolltype, @processtype, @period, @name"),
    "sp_pr_listadomarcas_web": ("database.py", "@cia, @Fechainicio, @FechaFin, @person"),
    "sp_pr_listaenvioalertas_web": ("database.py", "@cia"),
    "sp_pr_ListarSolicitudPermiso_web": ("database.py", "@cia, @person"),
    "sp_pr_registrarcomprobantes_web": (
        "database.py",
        "@cia, @payrolltype, @processtype, @period, @person, @userid, @filename, @tipo",
    ),
    "sp_pr_RegistrarSolicitudPermiso_web": (
        "database.py",
        "@cia, @person, @userid, @controlyear, @fechaini, @fechaFin, @comentario",
    ),
    "sp_pr_reportedescargas_web": ("database.py", "@cia, @tipodoc, @prperiod"),
    "sp_pr_reporteplame_total_web": ("app.py", "@cia, @payrolltype, @period, @person"),
    "sp_pr_reporteplamevertical_web": ("app.py", "@cia, @payrolltype, @process, @period, @person"),
    "sp_pr_selectorcompanias_web": ("app.py, database.py", "(sin parámetros)"),
    "sp_pr_selectorperiodos_web": ("app.py, database.py", "@cia, @payrolltype, @processtype"),
    "sp_pr_selectorpersonas_web": ("app.py", "@cia"),
    "sp_pr_selectorpersonasCA_web": ("app.py", "@cia, @fechaini, @fechafin"),
    "sp_pr_selectorplanillas_web": ("app.py, database.py", "@cia"),
    "sp_pr_selectorprocesos_web": ("app.py, database.py", "@cia, @payrolltype"),
    "sp_pr_selectortipojus_web": ("app.py", "(sin parámetros)"),
    "sp_pr_vacacionesperson_web": ("database.py", "@cia, @person"),
    "SP_PR_ReportePromedioLiquidacion": ("app.py", "@cia, @payrolltype, @period, @person"),
}

SQL_HEADER = """SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

"""


def stub_content(name: str, usage: str, params: str) -> str:
    return f"""/*
  Procedimiento: {name}
  Uso en proyecto: {usage}
  Parámetros (desde Python): {params}

  NOTA: Este script es un marcador. El procedimiento no se encontró en la base
  conectada (.env) o aún no fue desplegado. Sincronizar desde SSMS:
  clic derecho en el SP → Script Stored Procedure as → ALTER To.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- TODO: pegar aquí la definición ALTER PROCEDURE desde SQL Server
-- EXEC {name} {params if params != '(sin parámetros)' else ''}
GO
"""


def main():
    sql_dir = ROOT / "sql"
    sql_dir.mkdir(exist_ok=True)

    conn = DatabaseConfig.get_connection()
    cur = conn.cursor()

    exported = []
    stubs = []

    for sp_name, (usage, params) in sorted(SP_USAGE.items(), key=lambda x: x[0].lower()):
        fname = sp_name.lower() + ".sql"
        path = sql_dir / fname

        cur.execute(
            """
            SELECT m.definition
            FROM sys.sql_modules m
            INNER JOIN sys.objects o ON m.object_id = o.object_id
            WHERE o.type IN ('P', 'PC') AND o.name = ?
            """,
            (sp_name,),
        )
        row = cur.fetchone()
        if not row or not row[0]:
            # intento case-insensitive
            cur.execute(
                """
                SELECT m.definition, o.name
                FROM sys.sql_modules m
                INNER JOIN sys.objects o ON m.object_id = o.object_id
                WHERE o.type IN ('P', 'PC') AND LOWER(o.name) = LOWER(?)
                """,
                (sp_name,),
            )
            row = cur.fetchone()

        if row and row[0]:
            body = row[0].strip()
            if not body.upper().startswith("SET ANSI_NULLS"):
                body = SQL_HEADER + body
            path.write_text(body + "\n", encoding="utf-8")
            exported.append(sp_name)
        else:
            if not path.exists() or path.stat().st_size < 200:
                path.write_text(stub_content(sp_name, usage, params), encoding="utf-8")
            stubs.append(sp_name)

    # README índice
    lines = [
        "# Procedimientos almacenados — Asistencia",
        "",
        "Un archivo `.sql` por cada SP referenciado en `app.py` / `database.py`.",
        "",
        "| Procedimiento | Origen | Parámetros | Estado |",
        "|---------------|--------|------------|--------|",
    ]
    for sp_name, (usage, params) in sorted(SP_USAGE.items(), key=lambda x: x[0].lower()):
        status = "exportado desde BD" if sp_name in exported else "marcador (no en BD actual)"
        lines.append(f"| `{sp_name}` | {usage} | {params} | {status} |")

    (sql_dir / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    cur.close()
    conn.close()

    print(f"Exportados desde BD: {len(exported)}")
    print(f"Marcadores (sin definición en BD): {len(stubs)}")
    print(f"Carpeta: {sql_dir}")


if __name__ == "__main__":
    main()
