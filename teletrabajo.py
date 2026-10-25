"""Teletrabajo Ley 31572 — programación de turnos + matriz de entregables."""
from calendar import monthrange
from datetime import date, datetime

from database import (
    DatabaseConfig,
    asegurar_pasos_flujo_solicitud,
    get_pasos_flujo_solicitud,
    crear_pasos_flujo_solicitud,
    resumir_estado_flujo_vacaciones,
    resolver_accion_flujo,
    _wf_tablas_listas,
    _wf_tiene_tipo_solicitud,
    _wf_marcar_paso,
)

DIAS_SEMANA = {
    1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 7: 'Dom',
}


def _next_line(cursor, table, company, person):
    cursor.execute(
        f"""
        SELECT ISNULL(MAX(Line), 0) + 1 FROM dbo.{table}
        WHERE Company = ? AND Person = ?
        """,
        (company, person),
    )
    return int((cursor.fetchone() or [1])[0] or 1)


def parse_dias_remotos(raw):
    """'2,4' → [2,4] (1=Lun..7=Dom)."""
    out = []
    for part in str(raw or '').split(','):
        part = part.strip()
        if not part:
            continue
        try:
            n = int(part)
        except ValueError:
            continue
        if 1 <= n <= 7:
            out.append(n)
    return sorted(set(out))


def label_dias_remotos(raw):
    nums = parse_dias_remotos(raw)
    if not nums:
        return '—'
    return ', '.join(DIAS_SEMANA.get(n, str(n)) for n in nums)


def get_o_crear_acuerdo(company, person, modalidad='PARCIAL'):
    """Devuelve acuerdo activo; si no existe, crea PARCIAL por defecto (demo)."""
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Modalidad, FechaInicio, FechaFin, LugarDeclarado, Activo
            FROM dbo.CA_TeletrabajoAcuerdo
            WHERE Company = ? AND Person = ?
            """,
            (cia, per),
        )
        row = cursor.fetchone()
        if not row:
            cursor.execute(
                """
                INSERT INTO dbo.CA_TeletrabajoAcuerdo (
                    Company, Person, Modalidad, FechaInicio, LugarDeclarado, Activo,
                    xlastuser, xlastdate
                ) VALUES (?, ?, ?, CAST(GETDATE() AS DATE), 'DOMICILIO DECLARADO', 1, 'SYSTEM',
                          CONVERT(varchar(19), GETDATE(), 120))
                """,
                (cia, per, str(modalidad or 'PARCIAL').upper()[:10]),
            )
            conn.commit()
            cursor.execute(
                """
                SELECT Modalidad, FechaInicio, FechaFin, LugarDeclarado, Activo
                FROM dbo.CA_TeletrabajoAcuerdo
                WHERE Company = ? AND Person = ?
                """,
                (cia, per),
            )
            row = cursor.fetchone()
        cursor.close()
        conn.close()
        if not row:
            return None
        mod = str(row[0] or 'PARCIAL').upper()
        return {
            'Modalidad': mod,
            'ModalidadLabel': (
                'Teletrabajo Total' if mod == 'TOTAL'
                else 'Teletrabajo Parcial (Híbrido)'
            ),
            'FechaInicio': row[1],
            'FechaFin': row[2],
            'LugarDeclarado': row[3] or 'DOMICILIO DECLARADO',
            'Activo': bool(row[4]),
        }
    except Exception as e:
        print(f'Error en get_o_crear_acuerdo: {e}')
        return None
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def get_dias_programados(company, person, year, month):
    """Lista de días del mes con modalidad P/R (aprobados)."""
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        y, m = int(year), int(month)
        inicio = date(y, m, 1)
        fin = date(y, m, monthrange(y, m)[1])
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Fecha, ModalidadDia, Lugar, RefLine
            FROM dbo.CA_TeletrabajoDia
            WHERE Company = ? AND Person = ? AND Fecha BETWEEN ? AND ?
            ORDER BY Fecha
            """,
            (cia, per, inicio, fin),
        )
        rows = []
        for r in cursor.fetchall():
            rows.append({
                'Fecha': r[0],
                'ModalidadDia': str(r[1] or 'P').upper()[:1],
                'Lugar': r[2],
                'RefLine': r[3],
            })
        cursor.close()
        conn.close()
        return rows
    except Exception as e:
        print(f'Error en get_dias_programados: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def calendario_mes(company, person, year, month):
    """Estructura para UI: lista de semanas con celdas {fecha, dow, modalidad, label}."""
    y, m = int(year), int(month)
    dias_db = {
        (d['Fecha'].date() if hasattr(d['Fecha'], 'date') else d['Fecha']): d
        for d in get_dias_programados(company, person, y, m)
    }
    first = date(y, m, 1)
    last_day = monthrange(y, m)[1]
    # Monday=0
    start_pad = first.weekday()  # 0=Lun
    cells = []
    for _ in range(start_pad):
        cells.append(None)
    for day in range(1, last_day + 1):
        f = date(y, m, day)
        info = dias_db.get(f)
        modalidad = (info or {}).get('ModalidadDia') or 'P'
        # Si no hay registro: asumir presencial en laborables; None en fin de semana sin data
        if not info and f.weekday() >= 5:
            modalidad = None
        cells.append({
            'fecha': f,
            'dia': day,
            'dow': f.isoweekday(),  # 1=Lun
            'modalidad': modalidad,
            'label': (
                'Remoto' if modalidad == 'R'
                else ('Presen.' if modalidad == 'P' else '')
            ),
            'lugar': (info or {}).get('Lugar'),
        })
    while len(cells) % 7:
        cells.append(None)
    weeks = [cells[i:i + 7] for i in range(0, len(cells), 7)]
    return weeks


def registrar_rol_teletrabajo(company, person, periodo, dias_remotos, motivo, user_id):
    """
    periodo: 'YYYY-MM'
    dias_remotos: list[int] 1=Lun..7=Dom o string '2,4'
    """
    if isinstance(dias_remotos, str):
        nums = parse_dias_remotos(dias_remotos)
    else:
        nums = sorted({int(x) for x in (dias_remotos or []) if 1 <= int(x) <= 7})
    if not nums:
        return False, None, 'Seleccione al menos un día remoto.'
    periodo_s = str(periodo or '').strip()
    if len(periodo_s) != 7 or periodo_s[4] != '-':
        return False, None, 'Periodo no válido (YYYY-MM).'
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        # Evitar otra solicitud pendiente del mismo periodo
        cursor.execute(
            """
            SELECT COUNT(*) FROM dbo.CA_TeletrabajoRolSolicitud
            WHERE Company = ? AND Person = ? AND Periodo = ? AND status = 'P'
            """,
            (cia, per, periodo_s),
        )
        if int((cursor.fetchone() or [0])[0] or 0) > 0:
            return False, None, 'Ya existe una solicitud pendiente para ese periodo.'
        line = _next_line(cursor, 'CA_TeletrabajoRolSolicitud', cia, per)
        dias_s = ','.join(str(n) for n in nums)
        cursor.execute(
            """
            INSERT INTO dbo.CA_TeletrabajoRolSolicitud (
                Company, Person, Line, Periodo, DiasRemotos, Motivo, status,
                registerdate, xlastuser, xlastdate
            ) VALUES (?, ?, ?, ?, ?, ?, 'P', GETDATE(), ?, CONVERT(varchar(19), GETDATE(), 120))
            """,
            (cia, per, line, periodo_s, dias_s, (motivo or '')[:500] or None,
             str(user_id or '').strip()[:20]),
        )
        crear_pasos_flujo_solicitud(cia, per, line, 'TELETRABAJO', cursor=cursor)
        conn.commit()
        cursor.close()
        conn.close()
        return True, line, None
    except Exception as e:
        print(f'Error en registrar_rol_teletrabajo: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, None, str(e)
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def get_historial_roles(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Line AS Id, Company, Person, Periodo, DiasRemotos, Motivo, status, registerdate
            FROM dbo.CA_TeletrabajoRolSolicitud
            WHERE Company = ? AND Person = ?
            ORDER BY registerdate DESC, Line DESC
            """,
            (str(company or '').strip(), str(person or '').strip()),
        )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        for r in rows:
            try:
                sid = int(r.get('Id'))
            except (TypeError, ValueError):
                continue
            if str(r.get('status') or '').upper() == 'P':
                asegurar_pasos_flujo_solicitud(
                    r.get('Company') or company, r.get('Person') or person, sid, 'TELETRABAJO'
                )
            pasos = get_pasos_flujo_solicitud(
                r.get('Company') or company, r.get('Person') or person, sid, 'TELETRABAJO'
            )
            r['flujo'] = resumir_estado_flujo_vacaciones(pasos, r.get('status'))
            r['pasos_flujo'] = pasos
            r['dias_label'] = label_dias_remotos(r.get('DiasRemotos'))
        return rows
    except Exception as e:
        print(f'Error en get_historial_roles: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def eliminar_rol_pendiente(company, person, line):
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        sid = int(line)
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        if _wf_tablas_listas(cursor) and _wf_tiene_tipo_solicitud(cursor):
            cursor.execute(
                """
                SELECT COUNT(*) FROM dbo.WF_SolicitudPaso
                WHERE Company = ? AND Person = ? AND Line = ?
                  AND TipoSolicitud = 'TELETRABAJO' AND Estado = 'A'
                """,
                (cia, per, sid),
            )
            if int((cursor.fetchone() or [0])[0] or 0) > 0:
                return False
            cursor.execute(
                """
                DELETE FROM dbo.WF_SolicitudPaso
                WHERE Company = ? AND Person = ? AND Line = ? AND TipoSolicitud = 'TELETRABAJO'
                """,
                (cia, per, sid),
            )
        cursor.execute(
            """
            DELETE FROM dbo.CA_TeletrabajoRolSolicitud
            WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
            """,
            (cia, per, sid),
        )
        ok = cursor.rowcount > 0
        conn.commit()
        cursor.close()
        conn.close()
        return ok
    except Exception as e:
        print(f'Error en eliminar_rol_pendiente: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def _materializar_dias_rol(cursor, company, person, line, periodo, dias_remotos, lugar, user_id):
    """Genera CA_TeletrabajoDia para el mes: remotos según patrón, resto laborable = presencial."""
    y, m = int(periodo[:4]), int(periodo[5:7])
    remotos = set(parse_dias_remotos(dias_remotos))
    last = monthrange(y, m)[1]
    user_s = str(user_id or '').strip()[:20]
    lugar_s = (lugar or 'DOMICILIO DECLARADO')[:255]
    for day in range(1, last + 1):
        f = date(y, m, day)
        dow = f.isoweekday()  # 1=Lun
        if dow >= 6:
            continue  # no programar fin de semana
        modalidad = 'R' if dow in remotos else 'P'
        cursor.execute(
            """
            MERGE dbo.CA_TeletrabajoDia AS t
            USING (SELECT ? AS Company, ? AS Person, ? AS Fecha) AS s
            ON t.Company = s.Company AND t.Person = s.Person AND t.Fecha = s.Fecha
            WHEN MATCHED THEN
                UPDATE SET ModalidadDia = ?, Lugar = ?, RefLine = ?, xlastuser = ?
            WHEN NOT MATCHED THEN
                INSERT (Company, Person, Fecha, ModalidadDia, Lugar, RefLine, registerdate, xlastuser)
                VALUES (?, ?, ?, ?, ?, ?, GETDATE(), ?);
            """,
            (
                company, person, f,
                modalidad, lugar_s if modalidad == 'R' else None, int(line), user_s,
                company, person, f, modalidad, lugar_s if modalidad == 'R' else None, int(line), user_s,
            ),
        )


def aprobar_paso_teletrabajo(
    company, person, line, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    conn = None
    try:
        user = str(approval_user or '').strip()[:20]
        info = resolver_accion_flujo(
            company, person, line, person_actor, profilecode,
            menus=menus, unrestricted=unrestricted, web_admin=web_admin,
            approval_userid=user, tipo_solicitud='TELETRABAJO',
        )
        if not info.get('can_approve'):
            return False, 'No tiene pendiente de aprobación en este rol.', info
        pend = info['paso_pendiente']
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cia = str(company or '').strip()
        per = str(person or '').strip()
        line_i = int(line)
        if not _wf_marcar_paso(
            cursor, cia, per, line_i, pend['Nivel'], 'A', user, observacion,
            tipo_solicitud='TELETRABAJO',
        ):
            conn.rollback()
            return False, 'El paso ya fue resuelto por otro usuario.', info

        if info.get('es_nivel_final'):
            cursor.execute(
                """
                SELECT Periodo, DiasRemotos, Motivo, status
                FROM dbo.CA_TeletrabajoRolSolicitud
                WHERE Company = ? AND Person = ? AND Line = ?
                """,
                (cia, per, line_i),
            )
            sol = cursor.fetchone()
            if not sol or str(sol[3] or '').upper() != 'P':
                conn.rollback()
                return False, 'La solicitud ya no está pendiente.', info
            cursor.execute(
                """
                UPDATE dbo.CA_TeletrabajoRolSolicitud
                SET status = 'A', ApprovalUser = ?, ApprovalDate = GETDATE(),
                    xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
                """,
                (user, user, cia, per, line_i),
            )
            lugar = 'DOMICILIO DECLARADO'
            cursor.execute(
                """
                SELECT TOP 1 LugarDeclarado FROM dbo.CA_TeletrabajoAcuerdo
                WHERE Company = ? AND Person = ?
                """,
                (cia, per),
            )
            ar = cursor.fetchone()
            if ar and ar[0]:
                lugar = ar[0]
            _materializar_dias_rol(
                cursor, cia, per, line_i, str(sol[0]), sol[1], lugar, user
            )
            msg = f'Rol {sol[0]} aprobado. Calendario de turnos actualizado.'
            resumen = {'codigo': 'APROBADO', 'label': 'Aprobado', 'chip': 'success', 'detalle': 'Aprobado'}
        else:
            cursor.execute(
                """
                UPDATE dbo.CA_TeletrabajoRolSolicitud
                SET xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
                """,
                (user, cia, per, line_i),
            )
            total = int((info.get('resumen') or {}).get('total_niveles') or 0)
            siguiente = int(pend.get('Nivel') or 0) + 1
            msg = f"Nivel {pend.get('Nivel')} aprobado. Pasa al siguiente nivel."
            resumen = {
                'codigo': 'EN_APROBACION',
                'label': f'En aprobación ({siguiente}/{total})' if total else 'En aprobación',
                'chip': 'info',
                'detalle': f'Nivel {siguiente}/{total}' if total else 'Siguiente nivel',
            }
        conn.commit()
        try:
            cursor.close()
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass
        conn = None
        info_out = dict(info)
        info_out['resumen'] = resumen
        info_out['can_approve'] = False
        info_out['can_reject'] = False
        return True, msg, info_out
    except Exception as e:
        print(f'Error en aprobar_paso_teletrabajo: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, str(e), {}
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def rechazar_paso_teletrabajo(
    company, person, line, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    motivo = str(observacion or '').strip()
    if not motivo:
        return False, 'El motivo de rechazo es obligatorio.', {}
    conn = None
    try:
        user = str(approval_user or '').strip()[:20]
        info = resolver_accion_flujo(
            company, person, line, person_actor, profilecode,
            menus=menus, unrestricted=unrestricted, web_admin=web_admin,
            approval_userid=user, tipo_solicitud='TELETRABAJO',
        )
        if not info.get('can_reject'):
            return False, 'No tiene pendiente de rechazo en este rol.', info
        pend = info['paso_pendiente']
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cia = str(company or '').strip()
        per = str(person or '').strip()
        line_i = int(line)
        if not _wf_marcar_paso(
            cursor, cia, per, line_i, pend['Nivel'], 'R', user, motivo,
            tipo_solicitud='TELETRABAJO',
        ):
            conn.rollback()
            return False, 'El paso ya fue resuelto por otro usuario.', info
        if _wf_tiene_tipo_solicitud(cursor):
            cursor.execute(
                """
                UPDATE dbo.WF_SolicitudPaso
                SET Estado = 'R', UserID = ?, FechaRespuesta = GETDATE(), Observacion = ?
                WHERE Company = ? AND Person = ? AND Line = ?
                  AND TipoSolicitud = 'TELETRABAJO' AND Estado = 'P'
                """,
                (user, f'Cerrado por rechazo en nivel {pend.get("Nivel")}'[:500],
                 cia, per, line_i),
            )
        cursor.execute(
            """
            UPDATE dbo.CA_TeletrabajoRolSolicitud
            SET status = 'R', ApprovalUser = ?, ApprovalDate = GETDATE(),
                Comments = ?, xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
            WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
            """,
            (user, motivo[:255], user, cia, per, line_i),
        )
        if cursor.rowcount <= 0:
            # verificar
            cursor.execute(
                """
                SELECT status FROM dbo.CA_TeletrabajoRolSolicitud
                WHERE Company = ? AND Person = ? AND Line = ?
                """,
                (cia, per, line_i),
            )
            row = cursor.fetchone()
            if not row or str(row[0] or '').upper() != 'R':
                conn.rollback()
                return False, 'No se pudo rechazar la solicitud.', info
        conn.commit()
        try:
            cursor.close()
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass
        conn = None
        return True, 'Rol de teletrabajo rechazado.', info
    except Exception as e:
        print(f'Error en rechazar_paso_teletrabajo: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, str(e), {}
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


# --- Matriz SERVIR ---

def listar_matriz(company, person, periodo=None):
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        if periodo:
            cursor.execute(
                """
                SELECT Line AS Id, Periodo, Actividad, Entregable, FechaLimite,
                       PorcentajeAvance, EstadoEval, ComentarioJefe, Comments, NombreSustento
                FROM dbo.CA_TeletrabajoMatriz
                WHERE Company = ? AND Person = ? AND Periodo = ?
                ORDER BY FechaLimite, Line
                """,
                (cia, per, str(periodo).strip()),
            )
        else:
            cursor.execute(
                """
                SELECT Line AS Id, Periodo, Actividad, Entregable, FechaLimite,
                       PorcentajeAvance, EstadoEval, ComentarioJefe, Comments, NombreSustento
                FROM dbo.CA_TeletrabajoMatriz
                WHERE Company = ? AND Person = ?
                ORDER BY Periodo DESC, FechaLimite, Line
                """,
                (cia, per),
            )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        return rows
    except Exception as e:
        print(f'Error en listar_matriz: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def registrar_actividad_matriz(company, person, periodo, actividad, entregable, fecha_limite, user_id):
    if not actividad or not entregable or not fecha_limite:
        return False, None, 'Complete actividad, entregable y fecha límite.'
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        periodo_s = str(periodo or '').strip() or datetime.now().strftime('%Y-%m')
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        line = _next_line(cursor, 'CA_TeletrabajoMatriz', cia, per)
        cursor.execute(
            """
            INSERT INTO dbo.CA_TeletrabajoMatriz (
                Company, Person, Line, Periodo, Actividad, Entregable, FechaLimite,
                PorcentajeAvance, EstadoEval, registerdate, xlastuser, xlastdate
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 'EN_PROCESO', GETDATE(), ?,
                      CONVERT(varchar(19), GETDATE(), 120))
            """,
            (
                cia, per, line, periodo_s,
                str(actividad)[:500], str(entregable)[:300], fecha_limite,
                str(user_id or '').strip()[:20],
            ),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return True, line, None
    except Exception as e:
        print(f'Error en registrar_actividad_matriz: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, None, str(e)
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def actualizar_avance_matriz(company, person, line, porcentaje, estado=None, user_id=None,
                             comentario_jefe=None, local_sustento=None, nombre_sustento=None):
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        sid = int(line)
        try:
            pct = float(porcentaje)
        except (TypeError, ValueError):
            pct = 0
        pct = max(0, min(100, pct))
        estado_s = str(estado or '').strip().upper() or None
        if not estado_s:
            if pct >= 100:
                estado_s = 'CUMPLIDO'
            elif pct > 0:
                estado_s = 'EN_PROCESO'
            else:
                estado_s = 'EN_PROCESO'
        if estado_s not in ('CUMPLIDO', 'EN_PROCESO', 'OBSERVADO'):
            estado_s = 'EN_PROCESO'
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        comments = None
        if local_sustento:
            comments = f'SUSTENTO_LOCAL:{str(local_sustento).strip()}'[:255]
        if comments:
            cursor.execute(
                """
                UPDATE dbo.CA_TeletrabajoMatriz
                SET PorcentajeAvance = ?, EstadoEval = ?,
                    ComentarioJefe = COALESCE(?, ComentarioJefe),
                    Comments = ?, NombreSustento = COALESCE(?, NombreSustento),
                    xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company = ? AND Person = ? AND Line = ?
                """,
                (
                    pct, estado_s,
                    (comentario_jefe or None),
                    comments, (nombre_sustento or None),
                    str(user_id or '').strip()[:20],
                    cia, per, sid,
                ),
            )
        else:
            cursor.execute(
                """
                UPDATE dbo.CA_TeletrabajoMatriz
                SET PorcentajeAvance = ?, EstadoEval = ?,
                    ComentarioJefe = COALESCE(?, ComentarioJefe),
                    xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company = ? AND Person = ? AND Line = ?
                """,
                (
                    pct, estado_s,
                    (comentario_jefe or None) if comentario_jefe is not None else None,
                    str(user_id or '').strip()[:20],
                    cia, per, sid,
                ),
            )
        ok = cursor.rowcount > 0
        conn.commit()
        cursor.close()
        conn.close()
        return ok
    except Exception as e:
        print(f'Error en actualizar_avance_matriz: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def eliminar_actividad_matriz(company, person, line):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            DELETE FROM dbo.CA_TeletrabajoMatriz
            WHERE Company = ? AND Person = ? AND Line = ?
            """,
            (str(company or '').strip(), str(person or '').strip(), int(line)),
        )
        ok = cursor.rowcount > 0
        conn.commit()
        cursor.close()
        conn.close()
        return ok
    except Exception as e:
        print(f'Error en eliminar_actividad_matriz: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass
