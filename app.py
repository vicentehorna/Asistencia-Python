import os
import sys
import logging
from datetime import date, datetime
from decimal import Decimal

from flask import Flask, render_template, request, redirect, url_for, flash, session, jsonify
from flask_login import LoginManager, login_user, login_required, logout_user, current_user
from dotenv import load_dotenv

from database import (
    User,
    get_datos_usuario_web,
    cambiar_password,
    get_db_connection,
    get_feriados_lista,
    guardar_feriado,
    eliminar_feriado,
    guardar_horario,
    DIAS_HORARIO_DISPLAY,
    get_companias_selector,
    get_horarios_resumen_por_compania,
    get_horario_detalle_api,
)

load_dotenv()
app = Flask(__name__)
app.secret_key = os.getenv('FLASK_SECRET_KEY', 'dev-key-123')

logging.getLogger('werkzeug').setLevel(logging.ERROR)
sys.stdout.reconfigure(line_buffering=True)

login_manager = LoginManager(app)
login_manager.login_view = 'login'
login_manager.login_message_category = 'info'


def ensure_user_session():
    """Asegura que company y person estén en sesión."""
    if not session.get('company') or not session.get('person'):
        info = get_datos_usuario_web(current_user.id)
        if info:
            session['company'], session['person'] = info['company'], info['person']
            return info
    return {'company': session.get('company'), 'person': session.get('person')}


@app.template_filter('importe')
def format_importe(value):
    try:
        return '{:,.2f}'.format(float(value or 0))
    except Exception:
        return '0.00'


@app.template_filter('pct')
def format_pct(value):
    try:
        return '{:.2f} %'.format(float(value or 0))
    except Exception:
        return '0.00 %'


@app.context_processor
def inject_now():
    return {'now': datetime.now()}


def _jsonable_value(value):
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.strftime('%d/%m/%Y')
    if isinstance(value, date):
        return value.strftime('%d/%m/%Y')
    return value


def _report_column_name(name):
    """La primera columna del SP no tiene alias; pyodbc puede devolver '' → periodo_fmt."""
    if name is None:
        return 'periodo_fmt'
    if isinstance(name, str) and not name.strip():
        return 'periodo_fmt'
    return name


def _normalize_pr_period(period_raw):
    """
    PRPeriod en BD es yyyymmdd (8 dígitos), p. ej. 20251212.
    Acepta también '2025-12-12' o '2025/12/12' por si el valor llegó formateado.
    """
    s = str(period_raw or '').strip().replace('-', '').replace('/', '')
    if len(s) >= 8 and s[:8].isdigit():
        return s[:8]
    return str(period_raw or '').strip()


def _report_params_from_json(req):
    """Extrae y normaliza los 4 parámetros del SP (mismo orden que SSMS)."""
    body = req.get_json(silent=True) or {}
    cia = str(body.get('cia') or '').strip()
    payrolltype = str(body.get('payrolltype') or '').strip()
    period = _normalize_pr_period(body.get('period'))
    person = str(body.get('person') or '').strip()
    if not (cia and payrolltype and period and person):
        return None
    return (cia, payrolltype, period, person)


def _fetch_first_nonempty_resultset(cursor):
    """
    Algunos SP devuelven resultsets vacíos antes del SELECT final;
    avanza con nextset() hasta encontrar filas (o se acaban los sets).
    """
    columns = []
    rows = []
    while True:
        if cursor.description:
            columns = [_report_column_name(c[0]) for c in cursor.description]
            rows = cursor.fetchall()
            if rows:
                return columns, rows
        if not cursor.nextset():
            break
    return columns, []


@login_manager.user_loader
def load_user(user_id):
    return User.get_user_by_id(user_id)


@app.route('/')
def login():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    return render_template('login.html')


@app.route('/login', methods=['POST'])
def login_post():
    user = User.validate_user(request.form.get('username'), request.form.get('password'))
    if user:
        login_user(user)
        ensure_user_session()
        return redirect(url_for('dashboard'))
    flash('Usuario o contraseña incorrectos.', 'error')
    return redirect(url_for('login'))


@app.route('/cambiar-password', methods=['POST'])
def change_password_route():
    username = (request.form.get('username') or '').strip()
    old_password = request.form.get('old_password') or ''
    new_password = request.form.get('new_password') or ''
    confirm = request.form.get('confirm_password') or ''
    if new_password != confirm:
        flash('Las contraseñas nuevas no coinciden.', 'error')
        return redirect(url_for('login'))
    user = User.validate_user(username, old_password)
    if not user:
        flash('Usuario o contraseña anterior incorrectos.', 'error')
        return redirect(url_for('login'))
    ok, msg = cambiar_password(user.id, old_password, new_password)
    flash(msg, 'success' if ok else 'error')
    return redirect(url_for('login'))


@app.route('/logout')
@login_required
def logout():
    session.clear()
    logout_user()
    return redirect(url_for('login'))


@app.route('/dashboard')
@login_required
def dashboard():
    return render_template('dashboard.html')


def _en_desarrollo(titulo):
    """Plantilla temporal hasta implementar cada pantalla."""
    return render_template('en_desarrollo.html', titulo=titulo)


@app.route('/reporte-resumen')
@login_required
def reporte_resumen():
    ensure_user_session()
    return render_template('reporte_resumen.html')


def _companias_permitidas_ids():
    return {str(c.get('id', '')).strip() for c in get_companias_selector() if c.get('id') is not None}


@app.route('/maestro-horarios')
@login_required
def maestro_horarios():
    ensure_user_session()
    companies = get_companias_selector()
    default_company = session.get('company') or ''
    if companies and default_company:
        ids = {str(c.get('id', '')).strip() for c in companies}
        if str(default_company).strip() not in ids and companies:
            default_company = companies[0].get('id', '')
    return render_template(
        'horarios.html',
        companies=companies,
        dias=DIAS_HORARIO_DISPLAY,
        default_company=default_company,
    )


@app.route('/api/horarios/lista', methods=['GET'])
@login_required
def api_horarios_lista():
    cia = (request.args.get('cia') or '').strip()
    if not cia or cia not in _companias_permitidas_ids():
        return jsonify([])
    data = get_horarios_resumen_por_compania(cia)
    return jsonify(data)


@app.route('/api/horarios/<int:id_horario>', methods=['GET'])
@login_required
def api_horario_detalle(id_horario):
    cia = (request.args.get('cia') or '').strip()
    if not cia or cia not in _companias_permitidas_ids():
        return jsonify({"error": "Compañía no válida."}), 400
    det = get_horario_detalle_api(id_horario, cia)
    if not det:
        return jsonify({"error": "Horario no encontrado."}), 404
    return jsonify(det)


@app.route('/tipos-justificacion')
@login_required
def tipos_justificacion():
    return _en_desarrollo('Tipos de Justificación')


@app.route('/feriados')
@login_required
def feriados_page():
    lista = get_feriados_lista()
    return render_template('feriados.html', feriados=lista)


@app.route('/api/feriados/guardar', methods=['POST'])
@login_required
def api_guardar_feriado():
    data = request.get_json(silent=True) or {}
    fecha = (data.get('fecha') or '').strip()
    motivo = (data.get('motivo') or '').strip()
    es_recuperable = bool(data.get('esRecuperable'))

    if not fecha or not motivo:
        return jsonify({"success": False, "error": "Fecha y motivo son obligatorios."}), 400

    success = guardar_feriado(fecha, motivo, es_recuperable, current_user.id)
    return jsonify({"success": success})


@app.route('/api/feriados/eliminar/<int:id_feriado>', methods=['DELETE'])
@login_required
def api_eliminar_feriado(id_feriado):
    success = eliminar_feriado(id_feriado)
    return jsonify({"success": success})


@app.route('/api/horarios/guardar', methods=['POST'])
@login_required
def api_guardar_horario():
    ensure_user_session()
    data = request.get_json(silent=True) or {}
    company = (data.get('company') or data.get('cia') or '').strip()
    if not company or company not in _companias_permitidas_ids():
        return jsonify({"success": False, "error": "Seleccione una compañía válida."}), 400

    nombre = (data.get('nombreHorario') or '').strip()
    if not nombre:
        return jsonify({"success": False, "error": "Indique el nombre del horario."}), 400

    tolerancia = data.get('toleranciaMinutos', data.get('tolerancia'))
    dias = data.get('dias')
    if not isinstance(dias, dict):
        return jsonify({"success": False, "error": "Datos de la grilla semanal inválidos."}), 400

    id_horario = data.get('idHorario') or data.get('id_horario')
    ok, err, new_id = guardar_horario(nombre, tolerancia, company, dias, id_horario=id_horario)
    if ok:
        return jsonify({"success": True, "id": new_id})
    return jsonify({"success": False, "error": err or "No se pudo guardar el horario."}), 500


@app.route('/gestion-marcas')
@login_required
def gestion_marcas():
    return _en_desarrollo('Gestión de Marcas')


@app.route('/justificaciones')
@login_required
def justificaciones():
    return _en_desarrollo('Justificaciones')


@app.route('/procesar-asistencia')
@login_required
def procesar_asistencia():
    return _en_desarrollo('Procesar Asistencia')


@app.route('/reporte-liquidaciones')
@login_required
def reporte_liquidaciones():
    # La página carga vacía; los filtros se llenan por JS vía APIs.
    return render_template('reporte_liquidaciones.html')


@app.route('/reporte-planilla-vertical')
@login_required
def reporte_planilla_vertical_page():
    return render_template('reporte_planilla_vertical.html')


# ==========================================
# APIS PARA SELECTORES EN CASCADA (stored procedures)
# ==========================================


@app.route('/api/selectores/companias')
@login_required
def api_companias():
    """sp_pr_selectorcompanias_web → Company, description (@cia para el resto)."""
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_selectorcompanias_web")
        rows = cursor.fetchall()
        data = [{"id": r.Company, "text": r.description} for r in rows]
        return jsonify(data)
    except Exception:
        logging.exception("api_companias")
        return jsonify([])
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


@app.route('/api/selectores/planillas')
@login_required
def api_planillas():
    """sp_pr_selectorplanillas_web @cia → payrolltype, tipoplanilla"""
    cia = request.args.get('cia')
    if not cia:
        return jsonify([])
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_selectorplanillas_web @cia=?", (cia,))
        rows = cursor.fetchall()
        data = [{"id": r.payrolltype, "text": r.tipoplanilla} for r in rows]
        return jsonify(data)
    except Exception:
        logging.exception("api_planillas")
        return jsonify([])
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


@app.route('/api/selectores/procesos')
@login_required
def api_procesos():
    """sp_pr_selectorprocesos_web @cia, @payrolltype → processtype, proceso"""
    cia = request.args.get('cia')
    payrolltype = request.args.get('payrolltype')
    if not cia or not payrolltype:
        return jsonify([])
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_selectorprocesos_web @cia=?, @payrolltype=?",
            (cia, payrolltype),
        )
        rows = cursor.fetchall()
        data = [{"id": r.processtype, "text": r.proceso} for r in rows]
        return jsonify(data)
    except Exception:
        logging.exception("api_procesos")
        return jsonify([])
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


@app.route('/api/selectores/periodos')
@login_required
def api_periodos():
    """sp_pr_selectorperiodos_web @cia, @payrolltype, @processtype → period, periodo"""
    cia = request.args.get('cia')
    payrolltype = request.args.get('payrolltype')
    processtype = request.args.get('processtype')
    if not all([cia, payrolltype, processtype]):
        return jsonify([])
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_selectorperiodos_web @cia=?, @payrolltype=?, @processtype=?",
            (cia, payrolltype, processtype),
        )
        rows = cursor.fetchall()
        data = [{"id": r.period, "text": r.periodo} for r in rows]
        return jsonify(data)
    except Exception:
        logging.exception("api_periodos")
        return jsonify([])
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


@app.route('/api/selectores/trabajadores')
@login_required
def api_trabajadores():
    """sp_pr_selectorpersonas_web @cia → Person, Name"""
    cia = request.args.get('cia')
    if not cia:
        return jsonify([])
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_selectorpersonas_web @cia=?", (cia,))
        rows = cursor.fetchall()
        data = [{"id": r.Person, "text": r.Name} for r in rows]
        return jsonify(data)
    except Exception:
        logging.exception("api_trabajadores")
        return jsonify([])
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


# ==========================================
# API REPORTE ASISTENCIA
# ==========================================


@app.route('/api/reportes/resumen-asistencia', methods=['POST'])
@login_required
def api_reporte_resumen_asistencia():
    """sp_ca_ReporteResumenAsistencia_web @cia, @fechaini, @fechafin, @person."""
    body = request.get_json(silent=True) or {}
    cia = (body.get('cia') or '').strip()
    fechaini = (body.get('fechaini') or '').strip()
    fechafin = (body.get('fechafin') or '').strip()
    person = (body.get('person') or '0').strip() or '0'

    if not cia:
        return jsonify({"error": "Seleccione una compañía."}), 400
    if not fechaini or not fechafin:
        return jsonify({"error": "Debe indicar fecha inicio y fecha fin."}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_ca_ReporteResumenAsistencia_web @cia=?, @fechaini=?, @fechafin=?, @person=?",
            (cia, fechaini, fechafin, person),
        )
        columns, rows = _fetch_first_nonempty_resultset(cursor)
        if not rows:
            return jsonify([])

        data = []
        for row in rows:
            item = {}
            for col, val in zip(columns, row):
                key = str(col).strip().lower()
                item[key] = _jsonable_value(val)
            data.append(item)
        return jsonify(data)
    except Exception as e:
        logging.exception("api_reporte_resumen_asistencia")
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


# ==========================================
# API REPORTE PRINCIPAL
# ==========================================


@app.route('/api/reportes/promedio-liquidaciones', methods=['POST'])
@login_required
def api_reporte_promedio_liq():
    """SP_PR_ReportePromedioLiquidacion @cia, @payrolltype, @period, @person (varchar)."""
    params = _report_params_from_json(request)
    if not params:
        return jsonify([])
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC SP_PR_ReportePromedioLiquidacion @cia=?, @payrolltype=?, @period=?, @person=?",
            params,
        )
        columns, rows = _fetch_first_nonempty_resultset(cursor)
        if not rows:
            return jsonify([])
        data = [{col: _jsonable_value(val) for col, val in zip(columns, row)} for row in rows]
        return jsonify(data)
    except Exception:
        logging.exception("api_reporte_promedio_liq params=%s", params)
        return jsonify([])
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def _row_dict_lower(cursor, row):
    """Convierte una fila pyodbc en dict con claves en minúsculas."""
    if not cursor.description:
        return {}
    return {
        str(col[0]).strip().lower(): row[i]
        for i, col in enumerate(cursor.description)
    }


def _row_dict_from_columns(column_names, row):
    """Igual que _row_dict_lower pero con nombres ya capturados (tras nextset)."""
    return {
        str(column_names[i]).strip().lower(): row[i]
        for i in range(len(column_names))
    }


def _drain_all_cursor_resultsets(cursor):
    """Consume todos los lotes devueltos por un SP (SET NOCOUNT off, varios SELECT, etc.)."""
    while True:
        if cursor.description:
            try:
                cursor.fetchall()
            except Exception:
                pass
        if not cursor.nextset():
            break


def _fetch_last_query_resultset(cursor):
    """
    SPs con CREATE/INSERT/UPDATE antes del SELECT no dejan un result set en el primer lote;
    pyodbc exige no hacer fetchall() si no hay consulta. Tomamos el último lote con description.
    """
    last_cols = None
    last_rows = None
    while True:
        if cursor.description:
            last_cols = [str(c[0]).strip() for c in cursor.description]
            last_rows = cursor.fetchall()
        if not cursor.nextset():
            break
    return last_cols or [], last_rows or []


def _float_sp_cell(value):
    if value is None:
        return 0.0
    if isinstance(value, Decimal):
        return float(value)
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


@app.route('/reporte-resumen-total')
@login_required
def reporte_resumen_total():
    return render_template('reporte_resumen_total.html')


@app.route('/reporte_resumen_total', methods=['POST'])
@login_required
def reporte_resumen_total_post():
    """sp_pr_reporteplame_total_web: resumen por concepto y tipo (Mensual, Semanal, …)."""
    body = request.get_json(silent=True) or {}
    cia = (body.get('cia') or '').strip()
    payroll_type = (body.get('payroll_type') or '').strip()
    period = (body.get('period') or '').strip()

    if not cia:
        return jsonify({"error": "Seleccione una compañía."}), 400
    if not payroll_type or not period:
        return jsonify({"error": "Debe indicar tipo de planilla y periodo."}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_reporteplame_total_web @cia=?, @payrolltype=?, @period=?, @person=?",
            (cia, payroll_type, period, None),
        )
        col_names, rows = _fetch_last_query_resultset(cursor)
        resumen = []
        for row in rows:
            rd = _row_dict_from_columns(col_names, row)
            mensual = _float_sp_cell(rd.get('mensual'))
            semanal = _float_sp_cell(rd.get('semanal'))
            liquida = _float_sp_cell(rd.get('liquida'))
            vacaciones = _float_sp_cell(rd.get('vacaciones'))
            cts = _float_sp_cell(rd.get('cts'))
            grati = _float_sp_cell(rd.get('grati'))
            total_fila = mensual + semanal + liquida + vacaciones + cts + grati

            tipo_raw = rd.get('tipo')
            tipo = tipo_raw.strip() if isinstance(tipo_raw, str) else (str(tipo_raw).strip() if tipo_raw is not None else '')

            pdt_val = rd.get('pdt')
            concepto_val = rd.get('concepto')

            resumen.append(
                {
                    "tipo": tipo,
                    "pdt": '' if pdt_val is None else str(pdt_val).strip(),
                    "concepto": '' if concepto_val is None else str(concepto_val).strip(),
                    "mensual": mensual,
                    "semanal": semanal,
                    "liquida": liquida,
                    "vacaciones": vacaciones,
                    "cts": cts,
                    "grati": grati,
                    "total": total_fila,
                }
            )
        return jsonify(resumen)
    except Exception as e:
        logging.exception("reporte_resumen_total_post")
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


@app.route('/reporte_planilla_vertical', methods=['POST'])
@login_required
def reporte_planilla_vertical_post():
    """
    sp_pr_reporteplamevertical_web @cia, @payrolltype, @process, @period, @person.
    Cabeceras dinámicas desde xx_plamevertical2 + PR_Concept; datos desde xx_reporteplanilla.
    """
    body = request.get_json(silent=True) or {}
    cia = (body.get('cia') or '').strip()
    payroll_type = (body.get('payroll_type') or body.get('payrolltype') or '').strip()
    process = (body.get('process') or '').strip()
    period = _normalize_pr_period(body.get('period'))
    person = (body.get('person') or '0').strip() or '0'

    if not cia:
        return jsonify({"error": "Seleccione una compañía."}), 400
    if not payroll_type or not process or not period:
        return jsonify({"error": "Debe indicar tipo de planilla, proceso y periodo."}), 400

    static_headers_es = [
        'Código',
        'Nombre',
        'F.Ingreso',
        'F.Cese',
        'Cargo',
        'AFP',
        'C.Costo',
        'Cod.Costo',
        'Unidad',
        'TipoPago',
        'Perfil',
        'Horas',
        'Banco',
        'Num. Cuenta',
    ]
    static_keys = [
        'person',
        'name',
        'entrydate',
        'ceasedate',
        'position',
        'afp',
        'ccname',
        'costcenter',
        'unidad',
        'tipopago',
        'profile',
        'horas',
        'banco',
        'numcuenta',
    ]

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_reporteplamevertical_web @cia=?, @payrolltype=?, @process=?, @period=?, @person=?",
            (cia, payroll_type, process, period, person),
        )
        _drain_all_cursor_resultsets(cursor)

        cursor.execute(
            """
            SELECT DISTINCT UPPER(PR_Concept.PrintText) AS conceptname, PR_Concept.reporden
            FROM xx_plamevertical2
            INNER JOIN PR_Concept ON (
                xx_plamevertical2.conceptname = PR_Concept.Description
                AND PR_Concept.Company = ?
            )
            ORDER BY PR_Concept.reporden ASC, 1 ASC
            """,
            (cia,),
        )
        concept_rows = cursor.fetchall()
        conceptos_dinamicos = []
        for crow in concept_rows:
            cname = crow[0] if crow[0] is not None else ''
            cname = str(cname).strip()
            if cname:
                conceptos_dinamicos.append(cname)

        headers = list(static_headers_es) + conceptos_dinamicos
        num_concepts = len(conceptos_dinamicos)

        # Mismo SELECT que el SP (@grupo = 'N'): no usar SELECT * sobre la tabla,
        # porque position/costcenter almacenan IDs; el SP expone descripción y CCCode.
        concept_cols_sql = ", ".join(f"concept{str(i).zfill(2)}" for i in range(1, 66))
        sql_datos = f"""
            SELECT
                person,
                name,
                entrydate,
                ceasedate,
                (SELECT Description FROM PR_Position WHERE Position = xx_reporteplanilla.position) AS position,
                afp,
                (SELECT Description FROM AC_CostCenter WHERE CostCenter = xx_reporteplanilla.costcenter) AS ccname,
                (SELECT CCCode FROM AC_CostCenter WHERE CostCenter = xx_reporteplanilla.costcenter) AS costcenter,
                (SELECT Description FROM SY_ReplicationUnit
                 INNER JOIN SY_Person ON (SY_ReplicationUnit.ReplicationUnit = SY_Person.ReplicationUnit)
                 WHERE SY_Person.Person = xx_reporteplanilla.person) AS unidad,
                (SELECT CASE WHEN ISNULL(SY_Person.isrecruiter, 'N') = 'Y' THEN 'H' ELSE 'P' END
                 FROM sy_person WHERE person = xx_reporteplanilla.person) AS tipopago,
                (SELECT description FROM PR_AccountProfile
                 INNER JOIN PR_Employee ON (
                     PR_AccountProfile.AccountProfile = PR_Employee.AccountProfile
                     AND PR_AccountProfile.company = ?
                     AND PR_Employee.Person = xx_reporteplanilla.person)) AS profile,
                (SELECT SUM(hourday) FROM PR_REGISTERHOUR
                 WHERE period = ? AND Company = ? AND person = xx_reporteplanilla.person) AS horas,
                CASE WHEN (
                    SELECT ShortName FROM PR_ProcessType
                    WHERE Company = ? AND ProcessType = ?
                ) = 'CTS' THEN (
                    SELECT name FROM ERP_Bank
                    INNER JOIN PR_Employee ON (
                        ERP_Bank.Bank = PR_Employee.CTSBank
                        AND ERP_Bank.company = ?
                        AND PR_Employee.Person = xx_reporteplanilla.person)
                ) ELSE (
                    SELECT name FROM ERP_Bank
                    INNER JOIN PR_Employee ON (
                        ERP_Bank.Bank = PR_Employee.SalaryBank
                        AND ERP_Bank.company = ?
                        AND PR_Employee.Person = xx_reporteplanilla.person)
                ) END AS banco,
                CASE WHEN (
                    SELECT ShortName FROM PR_ProcessType
                    WHERE Company = ? AND ProcessType = ?
                ) = 'CTS' THEN (
                    SELECT CTSAccount FROM PR_Employee
                    WHERE PR_Employee.Person = xx_reporteplanilla.person AND PR_Employee.Company = ?
                ) ELSE (
                    SELECT salaryaccount FROM PR_Employee
                    WHERE PR_Employee.Person = xx_reporteplanilla.person AND PR_Employee.Company = ?
                ) END AS numcuenta,
                {concept_cols_sql}
            FROM xx_reporteplanilla
            ORDER BY name
        """
        params_datos = (
            cia,
            period,
            cia,
            cia,
            process,
            cia,
            cia,
            cia,
            process,
            cia,
            cia,
        )
        cursor.execute(sql_datos, params_datos)
        desc = cursor.description
        if not desc:
            return jsonify({"headers": headers, "data": []})
        col_names = [str(c[0]).strip().lower() for c in desc]
        rows = cursor.fetchall()

        resultado = []
        for row in rows:
            rd = {col_names[i]: row[i] for i in range(len(col_names))}
            fila = []
            for key in static_keys:
                fila.append(_jsonable_value(rd.get(key)))
            for i in range(num_concepts):
                cn = f"concept{str(i + 1).zfill(2)}"
                fila.append(_float_sp_cell(rd.get(cn)))
            resultado.append(fila)

        return jsonify({"headers": headers, "data": resultado})
    except Exception as e:
        logging.exception("reporte_planilla_vertical_post")
        return jsonify({"error": str(e)}), 500
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


# --- Rutas legacy (intranet): recuperar desde control de versiones al implementar Planillas ---
#
# @app.route('/datos-personales') → datos_personales
# @app.route('/resumen-ausencias') → resumen_ausencias
# @app.route('/solicitud-permisos') → solicitud_permisos
# @app.route('/documentos-personales') → documentos_personales
# @app.route('/descargar-archivo/<filename>') → descargar_archivo
# @app.route('/solicitudes-pendientes') → solicitudes_pendientes
# @app.route('/api/eventos') → api_eventos
# Helpers: fetch_pdf_file, get_sftp_client; imports: requests, paramiko, pdfkit, pyodbc, openpyxl, sendgrid, etc.

if __name__ == '__main__':
    port = int(os.getenv('FLASK_PORT', '5000'))
    app.run(debug=True, host='0.0.0.0', port=port)
