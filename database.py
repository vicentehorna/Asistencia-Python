import os
import pyodbc
import platform
from flask_login import UserMixin
from dotenv import load_dotenv

# Cargar variables de entorno desde .env
load_dotenv()


class DatabaseConfig:
    """Configuración de conexión a SQL Server"""
    
    @staticmethod
    def get_connection_string():
        """Construye la cadena de conexión a SQL Server"""
        # server = '179.61.14.224,1433'
        # database = 'hm_ultra2'
        # username = 'sa'
        # password = 'HMplanillas2020'

        server = os.getenv('SQL_SERVER')
        database = os.getenv('SQL_DATABASE')
        username = os.getenv('SQL_USER')
        password = os.getenv('SQL_PASSWORD')


        print(f"DEBUG: Intentando conectar a SERVER: {server} | DB: {database}")
        

        if platform.system() == 'Windows':
            driver = '{SQL Server}'
           
        else:
           driver = 'ODBC Driver 17 for SQL Server'

        print(f"DEBUG: Intentando conectar a [{server}] usando el driver: {driver}")

        connection_string = (
            f'DRIVER={driver};'
            f'SERVER={server};'
            f'DATABASE={database};'
            f'UID={username};'
            f'PWD={password};'
            'Encrypt=no;'
            'TrustServerCertificate=yes;' # <--- ESTO EVITA EL ERROR 53 EN MUCHOS CASOS
            'Connection Timeout=10;'
        )

           
        
        return connection_string
    
    @staticmethod
    def get_connection():
        """Crea y retorna una conexión a SQL Server"""
        try:
            conn = pyodbc.connect(DatabaseConfig.get_connection_string())
            return conn
        except Exception as e:
            print(f"Error al conectar con SQL Server: {e}")
            raise


def get_db_connection():
    """Conexión pyodbc reutilizable (APIs, reportes)."""
    return DatabaseConfig.get_connection()


class User(UserMixin):
    """Clase de usuario para Flask-Login"""
    
    def __init__(self, user_id, username, email=None, nombre=None):
        self.id = user_id
        self.username = username
        self.email = email
        self.nombre = nombre
    
    @staticmethod
    def validate_user(username, password):
        """
        Valida las credenciales del usuario contra la base de datos
        
        Args:
            username: Nombre de usuario
            password: Contraseña del usuario
            
        Returns:
            User object si las credenciales son válidas, None en caso contrario
        """
        try:
            conn = DatabaseConfig.get_connection()
            cursor = conn.cursor()
            
            # Query para validar usuario y contraseña
            # Ajusta el nombre de la tabla y columnas según tu esquema
            query = """
                SELECT 
                u.UserID,
                p.Name,
                p.email,
                'Autónomo'
            FROM SY_User u
            INNER JOIN SY_Person p ON p.UserID = u.UserID 
            INNER JOIN PR_Employee E on (p.Person = e.Person and e.Status = 'N')
            INNER JOIN SY_Company c ON (E.Company = c.Company)
            INNER JOIN SY_UserProfile up ON up.UserID = u.UserID
            INNER JOIN PR_mapping2 M on (c.Company = M.company)
            WHERE u.UserID = ? AND u.PasswordWeb = ?
            """
            
            cursor.execute(query, (username, password))
            row = cursor.fetchone()
            
            cursor.close()
            conn.close()

            print(f"DEBUG: Intentando login con usuario: '{username}'")
            
            if row:
                user_id, username_db, email, nombre = row
                return User(user_id, username_db, email, nombre)
            
            return None
            
        except Exception as e:
            print(f"Error al validar usuario: {e}")
            return None
    
    @staticmethod
    def get_user_by_id(user_id):
        """
        Obtiene un usuario por su ID
        
        Args:
            user_id: ID del usuario
            
        Returns:
            User object si existe, None en caso contrario
        """
        try:
            conn = DatabaseConfig.get_connection()
            cursor = conn.cursor()
            
            query = """
              SELECT 
                u.UserID,
                p.Name,
                p.email,
                'Autónomo'
            FROM SY_User u
            INNER JOIN SY_Person p ON p.UserID = u.UserID 
            INNER JOIN PR_Employee E on (p.Person = e.Person and e.Status = 'N')
            INNER JOIN SY_Company c ON (E.Company = c.Company)
            INNER JOIN SY_UserProfile up ON up.UserID = u.UserID
            INNER JOIN PR_mapping2 M on (c.Company = M.company)
            WHERE u.UserID = ?  
            """
            
            cursor.execute(query, (user_id,))
            row = cursor.fetchone()
            
            cursor.close()
            conn.close()
            
            if row:
                user_id_db, username, email, nombre = row
                return User(user_id_db, username, email, nombre)
            
            return None
            
        except Exception as e:
            print(f"Error al obtener usuario: {e}")
            return None


def get_datos_usuario_web(userid):
    """
    Ejecuta el SP sp_pr_datosusuario_web y retorna los datos del usuario.

    Args:
        userid: UserID / código de acceso (ej: current_user.id)

    Returns:
        dict con las columnas del SP o None si no hay resultado.
        Incluye entre otros: primerapellido, segundoapellido, nombres, TipoDocumento,
        NroDocumento, LugarNacimiento, FechaNacimiento, TelefonoFijo, Movil, email,
        Direccion, distrito, provincia, departamento, Fotografia, company, person,
        NivelInstruccion, Institucion, carrera, tipoempleado, FechaIngreso, tipocontrato,
        Regimenenpension, cussp, AsignacionFamiliar, Afpmixta, cargo, BancoSalario, etc.
    """
    cols_fallback = [
        'primerapellido', 'segundoapellido', 'nombres', 'TipoDocumento', 'NroDocumento',
        'LugarNacimiento', 'FechaNacimiento', 'TelefonoFijo', 'Movil', 'email', 'Direccion',
        'distrito', 'provincia', 'departamento', 'Fotografia', 'company', 'person',
        'NivelInstruccion', 'Institucion', 'carrera', 'tipoempleado', 'FechaIngreso',
        'tipocontrato', 'Regimenenpension', 'cussp', 'AsignacionFamiliar', 'Afpmixta',
        'BancoSalario', 'CuentaSalario', 'BancoCTS', 'CuentaCTS'
    ]
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_datosusuario_web ?", (userid,))
        row = cursor.fetchone()
        columns = [c[0] for c in cursor.description] if cursor.description else cols_fallback
        cursor.close()
        conn.close()

        print(f'Buscando datos para: {userid}')

        if not row:
            return None
        return dict(zip(columns, row))
    except Exception as e:
        print(f"Error en get_datos_usuario_web: {e}")
        return None


def cambiar_password(userid, clave_ant, clave_nueva):
    """
    Llama al SP sp_pr_CambiarPassword_web
    Retorna: (True, "mensaje") si es OK, o (False, "Mensaje de error") si es KO.
    """
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_CambiarPassword_web @userid=?, @clave_ant=?, @clave_nueva=?",
            (userid, clave_ant, clave_nueva)
        )
        # El SP hace UPDATE y luego SELECT; el driver puede devolver primero "rows affected".
        # Saltar a la result set del SELECT si fetchone falla con "No results".
        row = None
        try:
            row = cursor.fetchone()
        except Exception as e:
            if "No results" in str(e) and "not a query" in str(e):
                if cursor.nextset():
                    row = cursor.fetchone()
        cursor.close()
        if row:
            # SP devuelve: col0=resultado ('OK'/'KO'), col1=Mensaje
            resultado = (row[0] or '').strip().upper() if len(row) > 0 else ''
            mensaje = (row[1] or '').strip() if len(row) > 1 else ''
            if resultado == 'OK':
                conn.commit()
                return True, "Contraseña actualizada correctamente."
            return False, mensaje or "Error al cambiar la contraseña."
        return False, "Error desconocido al procesar la solicitud."
    except Exception as e:
        print(f"Error en cambiar_password: {e}")
        import traceback
        traceback.print_exc()
        return False, f"Error: {str(e)}"
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def get_vacaciones_detalle(company, person):
    """Obtiene el detalle de vacaciones ejecutando sp_pr_vacacionesperson_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_vacacionesperson_web @cia=?, @person=?", (company, person))
        
        # Obtener nombres de columnas
        columns = [column[0] for column in cursor.description]
        # Convertir a lista de diccionarios
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_vacaciones_detalle: {e}")
        return []


def get_ausencias_detalle(company, person):
    """Obtiene el detalle de ausencias ejecutando sp_pr_ausenciasperson_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_ausenciasperson_web @cia=?, @person=?", (company, person))
        
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_ausencias_detalle: {e}")
        return []


def _fecha_a_date(val):
    """Convierte valor de BD a date."""
    if val is None:
        return None
    if hasattr(val, 'date') and callable(getattr(val, 'date')):
        return val.date()
    if hasattr(val, 'isoformat'):
        from datetime import date as date_type
        return date_type.fromisoformat(str(val).split(' ')[0])
    return None


# Paleta de colores distintos por motivo de ausencia (evitar verde vacaciones y naranja feriado)
PALETA_AUSENCIAS = [
    '#722f37',  # marrón
    '#0d9488',  # teal
    '#1e40af',  # azul
    '#b45309',  # ámbar
    '#6b21a8',  # púrpura
    '#be185d',  # rosa
    '#0369a1',  # sky
    '#0f766e',  # teal oscuro
    '#4f46e5',  # índigo
    '#9d174d',  # rosa oscuro
    '#7c2d12',  # marrón oscuro
    '#6366f1',  # violeta
]


def _expandir_rango_a_dias(start_date, end_date):
    """Genera (start, end) por cada día del rango [start_date, end_date] inclusive. end en formato exclusivo (día siguiente)."""
    from datetime import timedelta
    if start_date is None or end_date is None:
        return []
    if start_date > end_date:
        return []
    out = []
    d = start_date
    while d <= end_date:
        start_str = d.isoformat()
        next_d = d + timedelta(days=1)
        end_str = next_d.isoformat()
        out.append((start_str, end_str))
        d = next_d
    return out


def get_eventos_calendario(company, person_id):
    """Obtiene vacaciones y ausencias para mostrar en el calendario. Expande rangos a un evento por día para que se vea cada día en la vista anual."""
    try:
        from datetime import timedelta
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        eventos = []

        # Ausencias (sp_pr_ausenciasperson_web: MotivoAusencia, FechaInicio, FechaFin, Dias, Tipo, Solicitud) — un evento por día, color único por motivo
        try:
            cursor.execute("EXEC sp_pr_ausenciasperson_web @cia=?, @person=?", (company, person_id))
            if cursor.description:
                columns = [c[0] for c in cursor.description]
                rows_ausencia = []
                for row in cursor.fetchall():
                    d = dict(zip(columns, row))
                    motivo = (d.get('MotivoAusencia') or d.get('title') or 'Ausencia').strip()
                    start = d.get('FechaInicio') or d.get('start')
                    end = d.get('FechaFin') or d.get('end')
                    if start and end:
                        rows_ausencia.append((motivo, start, end))
                motivos_unicos = sorted(set(m[0] for m in rows_ausencia))
                color_por_motivo = {m: PALETA_AUSENCIAS[i % len(PALETA_AUSENCIAS)] for i, m in enumerate(motivos_unicos)}
                for motivo, start, end in rows_ausencia:
                    start_d = _fecha_a_date(start)
                    end_d = _fecha_a_date(end)
                    color = color_por_motivo.get(motivo, PALETA_AUSENCIAS[0])
                    for start_str, end_str in _expandir_rango_a_dias(start_d, end_d):
                        eventos.append({
                            'title': motivo,
                            'start': start_str,
                            'end': end_str,
                            'tipo': 'ausencia',
                            'backgroundColor': color,
                            'borderColor': color,
                            'extendedProps': {'tipo': 'ausencia', 'motivo': motivo}
                        })
        except Exception as ex:
            print(f"Error obteniendo ausencias para calendario: {ex}")

        # Vacaciones (SP sp_pr_vacacionesperson_web: FechaInicio, FechaFin, Dias, anio, Solicitud) — un evento por día
        try:
            cursor.execute("EXEC sp_pr_vacacionesperson_web @cia=?, @person=?", (company, person_id))
            if cursor.description:
                columns = [c[0] for c in cursor.description]
                for row in cursor.fetchall():
                    d = dict(zip(columns, row))
                    start = d.get('FechaInicio') or d.get('start')
                    end = d.get('FechaFin') or d.get('end')
                    if start and end:
                        start_d = _fecha_a_date(start)
                        end_d = _fecha_a_date(end)
                        for start_str, end_str in _expandir_rango_a_dias(start_d, end_d):
                            eventos.append({'title': 'VAC', 'start': start_str, 'end': end_str, 'tipo': 'vacacion', 'extendedProps': {'tipo': 'vacacion'}})
        except Exception as ex:
            print(f"Error obteniendo vacaciones para calendario: {ex}")

        # Formatear fechas para JSON y asignar colores (ausencias ya tienen color por motivo)
        for ev in eventos:
            ev['start'] = ev['start'].isoformat() if hasattr(ev['start'], 'isoformat') else ev['start']
            ev['end'] = ev['end'].isoformat() if hasattr(ev['end'], 'isoformat') else ev['end']
            if ev.get('tipo') == 'vacacion':
                ev['backgroundColor'] = '#10b981'
                ev['borderColor'] = '#059669'
            elif ev.get('tipo') != 'ausencia':
                ev['backgroundColor'] = '#722f37'
                ev['borderColor'] = ev['backgroundColor']

        cursor.close()
        conn.close()
        return eventos
    except Exception as e:
        print(f"Error en get_eventos_calendario: {e}")
        return []


def get_feriados():
    """Obtiene los feriados desde SY_Holiday para mostrarlos en el calendario."""
    from datetime import date, timedelta
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT HolidayDate as fecha, Description as motivo FROM SY_Holiday")
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        feriados = []
        for row in rows:
            fecha = row[0]
            motivo = (row[1] or 'Feriado').strip()
            if not fecha:
                continue
            try:
                d = fecha.date() if hasattr(fecha, 'date') and callable(getattr(fecha, 'date')) else fecha
            except (AttributeError, TypeError):
                d = fecha
            start_str = d.isoformat() if hasattr(d, 'isoformat') else str(d).split(' ')[0]
            try:
                end_d = d + timedelta(days=1)
                end_str = end_d.isoformat()
            except (TypeError, AttributeError):
                end_str = start_str
            feriados.append({
                'title': motivo,
                'start': start_str,
                'end': end_str,
                'backgroundColor': '#f59e0b',
                'borderColor': '#d97706',
                'extendedProps': { 'tipo': 'feriado' }
            })
        return feriados
    except Exception as e:
        print(f"Error en get_feriados: {e}")
        return []


def get_feriados_lista():
    """Obtiene todos los feriados ordenados por fecha descendente."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT IdFeriado, Fecha, Motivo, EsRecuperable FROM CA_Feriados ORDER BY Fecha DESC"
        )
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_feriados_lista: {e}")
        return []


def guardar_feriado(fecha, motivo, es_recuperable, usuario):
    """Inserta un nuevo feriado en la tabla CA_Feriados."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO CA_Feriados (Fecha, Motivo, EsRecuperable, XLastUser, XLastDate)
            VALUES (?, ?, ?, ?, GETDATE())
            """,
            (fecha, motivo, 1 if es_recuperable else 0, usuario),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error al guardar feriado: {e}")
        return False


def eliminar_feriado(id_feriado):
    """Elimina un feriado por su ID."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM CA_Feriados WHERE IdFeriado = ?", (id_feriado,))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error al eliminar feriado: {e}")
        return False


def get_tipos_justificacion():
    """Lista de CA_TipoJustificacion ordenada por descripción."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT IdJustificacion, Descripcion, Abreviatura,
                   EsDiaCompleto, PagaHaber, RequiereSustento
            FROM CA_TipoJustificacion
            ORDER BY Descripcion
            """
        )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return rows
    except Exception as e:
        print(f"Error en get_tipos_justificacion: {e}")
        return []


def guardar_tipo_justificacion(data, usuario):
    """
    INSERT o UPDATE en CA_TipoJustificacion.
    data: descripcion, abreviatura, esDiaCompleto, pagaHaber, requiereSustento, idJustificacion (opcional).
    usuario: texto para xlastuser (máx. 20).
    Retorna (True, None) o (False, mensaje).
    """
    if not isinstance(data, dict):
        return False, 'Datos inválidos.'

    descripcion = (data.get('descripcion') or '').strip()
    abreviatura = (data.get('abreviatura') or '').strip()[:20]
    if not descripcion:
        return False, 'La descripción es obligatoria.'

    es_dia = 1 if data.get('esDiaCompleto') else 0
    paga = 1 if data.get('pagaHaber') else 0
    req = 1 if data.get('requiereSustento') else 0
    user = (str(usuario) if usuario is not None else '')[:20]

    jid = data.get('idJustificacion') if data.get('idJustificacion') is not None else data.get('id')
    if jid is not None and str(jid).strip() != '':
        try:
            jid = int(jid)
        except (TypeError, ValueError):
            jid = None
    else:
        jid = None

    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        if jid is not None and jid > 0:
            cursor.execute(
                """
                UPDATE CA_TipoJustificacion
                SET Descripcion = ?, Abreviatura = ?, EsDiaCompleto = ?, PagaHaber = ?, RequiereSustento = ?,
                    xlastuser = ?, xlastdate = GETDATE()
                WHERE IdJustificacion = ?
                """,
                (descripcion, abreviatura or None, es_dia, paga, req, user, jid),
            )
            if cursor.rowcount == 0:
                cursor.close()
                conn.close()
                return False, 'No se encontró el registro a actualizar.'
        else:
            cursor.execute(
                """
                INSERT INTO CA_TipoJustificacion
                    (Descripcion, Abreviatura, EsDiaCompleto, PagaHaber, RequiereSustento, xlastuser, xlastdate)
                VALUES (?, ?, ?, ?, ?, ?, GETDATE())
                """,
                (descripcion, abreviatura or None, es_dia, paga, req, user),
            )
        conn.commit()
        cursor.close()
        conn.close()
        return True, None
    except Exception as e:
        print(f"Error en guardar_tipo_justificacion: {e}")
        return False, str(e)


def eliminar_tipo_justificacion(id_justificacion):
    """Elimina un tipo de justificación por IdJustificacion."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM CA_TipoJustificacion WHERE IdJustificacion = ?",
            (int(id_justificacion),),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error en eliminar_tipo_justificacion: {e}")
        return False


def get_lista_envio_alertas(company):
    """
    Lista trabajadores con configuración de alertas (sp_pr_listaenvioalertas_web).
    Retorna filas {person, name, email, recibe_alertas}.
    """
    cia = (company or '').strip()[:4]
    if not cia:
        return []
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_pr_listaenvioalertas_web] @cia=?", (cia,))
        cols = [c[0] for c in cursor.description]
        out = []
        for row in cursor.fetchall():
            d = dict(zip(cols, row))
            lk = {str(k).lower(): v for k, v in d.items()}
            ra = lk.get('recibealertas')
            if isinstance(ra, bytes):
                ra = bool(ra[0]) if ra else False
            else:
                ra = bool(ra) if ra is not None else True
            out.append(
                {
                    'person': str(lk.get('person') or '').strip(),
                    'name': (lk.get('name') or '') or '',
                    'email': (lk.get('email') or lk.get('e_mail') or '') or '',
                    'recibe_alertas': ra,
                }
            )
        cursor.close()
        conn.close()
        return out
    except Exception as e:
        print(f"Error en get_lista_envio_alertas: {e}")
        return []


def actualizar_recibe_alertas(company, person, recibe_alertas, usuario):
    """
    Actualiza RecibeAlertas en CA_ConfiguracionAlertas.
    Retorna (True, None) o (False, mensaje).
    """
    cia = (company or '').strip()[:4]
    pers = (person or '').strip()[:20]
    user = (str(usuario) if usuario is not None else '')[:20]
    if not cia or not pers:
        return False, 'Compañía y trabajador son obligatorios.'
    bit_val = 1 if recibe_alertas else 0
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE CA_ConfiguracionAlertas
            SET RecibeAlertas = ?, XLastUser = ?, XLastDate = GETDATE()
            WHERE Company = ? AND Person = ?
            """,
            (bit_val, user, cia, pers),
        )
        if cursor.rowcount == 0:
            cursor.close()
            conn.close()
            return False, 'No se encontró configuración de alertas para ese trabajador en la compañía indicada.'
        conn.commit()
        cursor.close()
        conn.close()
        return True, None
    except Exception as e:
        print(f"Error en actualizar_recibe_alertas: {e}")
        return False, str(e)


def get_destinatarios_prueba_alertas_email(company):
    """
    Colaboradores con RecibeAlertas = 1 y correo en SY_Person (envío de prueba SMTP).
    Retorna lista de tuplas (nombre, email) sin duplicar direcciones (minúsculas).
    """
    cia = (company or '').strip()[:4]
    if not cia:
        return []
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT p.Name, p.EMail
            FROM CA_ConfiguracionAlertas ca
            INNER JOIN SY_Person p ON ca.Person = p.Person
            WHERE ca.Company = ?
              AND ca.RecibeAlertas = 1
              AND p.EMail IS NOT NULL
              AND LTRIM(RTRIM(p.EMail)) <> ''
            """,
            (cia,),
        )
        seen = set()
        out = []
        for row in cursor.fetchall():
            name = row[0]
            email = (str(row[1]).strip() if row[1] is not None else '')
            if not email:
                continue
            key = email.lower()
            if key in seen:
                continue
            seen.add(key)
            out.append((name, email))
        cursor.close()
        conn.close()
        return out
    except Exception as e:
        print(f"Error en get_destinatarios_prueba_alertas_email: {e}")
        return []


DIAS_HORARIO_ORDEN = [
    'Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes', 'Sabado', 'Domingo',
]

# (clave BD, etiqueta pantalla)
DIAS_HORARIO_DISPLAY = [
    ('Lunes', 'Lunes'),
    ('Martes', 'Martes'),
    ('Miercoles', 'Miércoles'),
    ('Jueves', 'Jueves'),
    ('Viernes', 'Viernes'),
    ('Sabado', 'Sábado'),
    ('Domingo', 'Domingo'),
]


def get_companias_selector():
    """Misma fuente que sp_pr_selectorcompanias_web → lista {id, text}."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_selectorcompanias_web")
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        return [{"id": r.Company, "text": r.description} for r in rows]
    except Exception as e:
        print(f"Error en get_companias_selector: {e}")
        return []


def _valor_json_marcas(v):
    """Serializa valores de filas para respuestas JSON."""
    if v is None:
        return None
    from datetime import date, datetime as dt
    from decimal import Decimal
    if isinstance(v, dt):
        return v.isoformat(sep=' ', timespec='seconds')
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, bytes):
        try:
            return v.decode('utf-8')
        except Exception:
            return str(v)
    return v


def get_listado_marcas(cia, fecha_inicio, fecha_fin, person):
    """
    Ejecuta sp_pr_listadomarcas_web.
    Retorna (lista_de_dicts_serializables, None) o ([], mensaje_error).
    """
    if not cia or not str(cia).strip():
        return [], 'Indique la compañía.'
    if not fecha_inicio or not fecha_fin:
        return [], 'Indique fecha inicio y fecha fin.'
    pers = (str(person).strip() if person is not None else '') or '0'

    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC dbo.sp_pr_listadomarcas_web @cia=?, @Fechainicio=?, @FechaFin=?, @person=?",
            (str(cia).strip(), fecha_inicio, fecha_fin, pers),
        )
        if not cursor.description:
            cursor.close()
            conn.close()
            return [], None
        cols = [c[0] for c in cursor.description]
        out = []
        for row in cursor.fetchall():
            rd = dict(zip(cols, row))
            out.append({k: _valor_json_marcas(val) for k, val in rd.items()})
        cursor.close()
        conn.close()
        return out, None
    except Exception as e:
        print(f"Error en get_listado_marcas: {e}")
        if conn:
            try:
                conn.close()
            except Exception:
                pass
        return [], str(e)


def _parse_fecha_hora_marca_manual(fecha_str, hora_str):
    """Combina fecha (YYYY-MM-DD) y hora (HH:MM o HH:MM:SS) en datetime."""
    from datetime import datetime

    if not fecha_str or not str(fecha_str).strip():
        raise ValueError("Indique la fecha.")
    h = (hora_str or "").strip()
    if not h:
        raise ValueError("Indique la hora (incluya segundos si aplica).")
    if "." in h:
        h = h.split(".", 1)[0]
    parts = h.split(":")
    if len(parts) == 2:
        h = f"{parts[0].zfill(2)}:{parts[1].zfill(2)}:00"
    elif len(parts) == 3:
        h = f"{parts[0].zfill(2)}:{parts[1].zfill(2)}:{parts[2].zfill(2)}"
    fecha = str(fecha_str).strip()[:10]
    return datetime.strptime(f"{fecha} {h}", "%Y-%m-%d %H:%M:%S")


def _lookup_id_trabajador_por_person(cursor, person, company):
    """
    Obtiene IdTrabajador desde dbo.Trabajadores.
    Si no hay coincidencia, retorna 1 (valor por defecto indicado en requerimiento).
    """
    person = str(person).strip()
    company_cmp = str(company).strip()[:4] if company else ""
    try:
        cursor.execute(
            """
            SELECT TOP 1 IdTrabajador
            FROM dbo.Trabajadores
            WHERE LTRIM(RTRIM(CAST(Person AS VARCHAR(50)))) = ?
              AND LTRIM(RTRIM(CAST(company AS CHAR(4)))) = ?
            """,
            (person, company_cmp),
        )
        row = cursor.fetchone()
        if row and row[0] is not None:
            return int(row[0])
    except Exception:
        pass
    try:
        cursor.execute(
            """
            SELECT TOP 1 IdTrabajador
            FROM dbo.Trabajadores
            WHERE LTRIM(RTRIM(CAST(Person AS VARCHAR(50)))) = ?
            """,
            (person,),
        )
        row = cursor.fetchone()
        if row and row[0] is not None:
            return int(row[0])
    except Exception:
        pass
    return 1


def insert_registro_asistencia_manual(cia, person, fecha_str, hora_str, motivo, xlastuser):
    """
    Inserta una marca manual en dbo.RegistroAsistencia.
    RutaFoto NULL, flagmanual 'Y', MotivoManual según usuario.
    IdTrabajador: lookup por Person/company; si no existe fila, 1.
    """
    from datetime import datetime

    conn = None
    try:
        fh = _parse_fecha_hora_marca_manual(fecha_str, hora_str)
    except ValueError as e:
        return False, str(e)

    person_db = str(person).strip()[:20] if person else ""
    if not person_db:
        return False, "Seleccione un trabajador."

    motivo_stripped = (motivo or "").strip()
    if not motivo_stripped:
        return False, "El motivo / sustento es obligatorio."

    company_db = str(cia).strip()[:4].ljust(4)[:4]
    motivo_db = motivo_stripped[:255]
    user_db = str(xlastuser or "").strip()[:20] if xlastuser else None
    now = datetime.now().replace(microsecond=0)

    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        id_trab = _lookup_id_trabajador_por_person(
            cursor, person_db, str(cia).strip()[:4]
        )
        cursor.execute(
            """
            INSERT INTO dbo.RegistroAsistencia (
                IdTrabajador,
                FechaHoraIngreso,
                RutaFoto,
                Person,
                company,
                xlastuser,
                xlastdate,
                flagmanual,
                MotivoManual
            )
            VALUES (?, ?, NULL, ?, ?, ?, ?, 'Y', ?)
            """,
            (id_trab, fh, person_db, company_db, user_db, now, motivo_db),
        )
        conn.commit()
        cursor.close()
        conn.close()
        return True, None
    except Exception as e:
        print(f"Error en insert_registro_asistencia_manual: {e}")
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
            try:
                conn.close()
            except Exception:
                pass
        return False, str(e)


def inactivar_registro_asistencia(cia, id_registro, xlastuser):
    """
    Establece estado = 'I' en RegistroAsistencia (oculta la marca en el listado).
    Retorna (True, None) o (False, mensaje).
    """
    from datetime import datetime

    company_db = str(cia).strip()[:4]
    if not company_db:
        return False, "Compañía no válida."
    try:
        rid = int(id_registro)
    except (TypeError, ValueError):
        return False, "Registro no válido."
    user_db = str(xlastuser or "").strip()[:20] if xlastuser else None
    now = datetime.now().replace(microsecond=0)

    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE dbo.RegistroAsistencia
            SET estado = 'I',
                xlastuser = ?,
                xlastdate = ?
            WHERE IdRegistro = ?
              AND LTRIM(RTRIM(company)) = ?
              AND estado = 'A'
            """,
            (user_db, now, rid, company_db),
        )
        if cursor.rowcount == 0:
            cursor.close()
            conn.close()
            return False, "No se encontró la marca activa o ya fue inactivada."
        conn.commit()
        cursor.close()
        conn.close()
        return True, None
    except Exception as e:
        print(f"Error en inactivar_registro_asistencia: {e}")
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
            try:
                conn.close()
            except Exception:
                pass
        return False, str(e)


def _format_time_for_input(val):
    """Normaliza time/timedelta/datetime a 'HH:MM' para input type=time."""
    if val is None:
        return ''
    from datetime import time, timedelta, datetime as dt
    if isinstance(val, time):
        return val.strftime('%H:%M')
    if isinstance(val, dt):
        return val.strftime('%H:%M')
    if isinstance(val, timedelta):
        secs = int(val.total_seconds()) % 86400
        h = secs // 3600
        m = (secs % 3600) // 60
        return f'{h:02d}:{m:02d}'
    s = str(val).strip()
    if len(s) >= 5 and s[2] == ':':
        return s[:5]
    return s


def _bit_si(val):
    if val is None:
        return False
    if isinstance(val, bool):
        return val
    s = str(val).strip().upper()
    return s in ('1', 'Y', 'TRUE', 'T')


def get_horarios_resumen_por_compania(company):
    """Listado compacto para sidebar: IdHorario, NombreHorario, ToleranciaMinutos."""
    if company is None or str(company).strip() == '':
        return []
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT IdHorario, NombreHorario, ISNULL(ToleranciaMinutos, 0) AS ToleranciaMinutos
            FROM Horarios
            WHERE Company = ?
            ORDER BY NombreHorario
            """,
            (str(company).strip(),),
        )
        cols = [c[0] for c in cursor.description]
        out = [dict(zip(cols, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return out
    except Exception as e:
        print(f"Error en get_horarios_resumen_por_compania: {e}")
        return []


def get_horario_detalle_api(id_horario, company):
    """
    Devuelve dict para JSON: idHorario, nombreHorario, toleranciaMinutos, dias{...}
    o None si no existe.
    """
    if not id_horario or company is None or str(company).strip() == '':
        return None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM Horarios WHERE IdHorario = ? AND Company = ?",
            (int(id_horario), str(company).strip()),
        )
        row = cursor.fetchone()
        cols = [c[0] for c in cursor.description] if cursor.description else []
        cursor.close()
        conn.close()
        if not row:
            return None
        rd = dict(zip(cols, row))

        def col(name):
            for k in rd:
                if str(k).lower() == name.lower():
                    return rd[k]
            return None

        dias = {}
        for dia in DIAS_HORARIO_ORDEN:
            dias[dia] = {
                'laborable': _bit_si(col(f'{dia}_Laborable')),
                'entrada': _format_time_for_input(col(f'{dia}_Entrada')),
                'salida': _format_time_for_input(col(f'{dia}_Salida')),
                'salidaRefri': _format_time_for_input(col(f'{dia}_SalidaRefri')),
                'entradaRefri': _format_time_for_input(col(f'{dia}_EntradaRefri')),
            }

        return {
            'idHorario': int(col('IdHorario') or 0),
            'nombreHorario': (col('NombreHorario') or '').strip() if col('NombreHorario') else '',
            'toleranciaMinutos': int(col('ToleranciaMinutos') or 0),
            'dias': dias,
        }
    except Exception as e:
        print(f"Error en get_horario_detalle_api: {e}")
        return None


def _hora_sql(val):
    """Convierte cadena de time del formulario a valor para SQL; vacío -> None."""
    s = (val or '').strip() if val is not None else ''
    if not s:
        return None
    return s


def guardar_horario(nombre_horario, tolerancia_minutos, company, dias, id_horario=None):
    """
    Inserta o actualiza un registro en Horarios.

    dias: dict con claves Lunes, Martes, Miercoles, ... cada una con:
        laborable (bool), entrada, salida, salidaRefri, entradaRefri (str o None)
    id_horario: si viene, ejecuta UPDATE para esa fila y compañía.
    Retorna (True, None, id) en éxito o (False, mensaje_error, None).
    """
    if not (nombre_horario or '').strip():
        return False, 'El nombre del horario es obligatorio.', None
    if company is None or str(company).strip() == '':
        return False, 'No hay compañía asignada.', None

    try:
        tol = int(tolerancia_minutos) if tolerancia_minutos is not None else 0
    except (TypeError, ValueError):
        tol = 0

    valores_dia = []
    for dia in DIAS_HORARIO_ORDEN:
        d = dias.get(dia) if isinstance(dias, dict) else None
        if not isinstance(d, dict):
            d = {}
        lab = bool(d.get('laborable'))
        valores_dia.extend(
            [
                1 if lab else 0,
                _hora_sql(d.get('entrada')),
                _hora_sql(d.get('salida')),
                _hora_sql(d.get('salidaRefri')),
                _hora_sql(d.get('entradaRefri')),
            ]
        )

    cols_dia = []
    for dia in DIAS_HORARIO_ORDEN:
        cols_dia.extend(
            [
                f'{dia}_Laborable',
                f'{dia}_Entrada',
                f'{dia}_Salida',
                f'{dia}_SalidaRefri',
                f'{dia}_EntradaRefri',
            ]
        )

    company_s = str(company).strip()
    nombre_s = nombre_horario.strip()

    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()

        hid = id_horario
        if hid is not None:
            try:
                hid = int(hid)
            except (TypeError, ValueError):
                hid = None
        if hid is not None and hid > 0:
            set_parts = ['NombreHorario = ?', 'ToleranciaMinutos = ?']
            params_up = [nombre_s, tol]
            for i, dia in enumerate(DIAS_HORARIO_ORDEN):
                base = i * 5
                set_parts.extend(
                    [
                        f'{dia}_Laborable = ?',
                        f'{dia}_Entrada = ?',
                        f'{dia}_Salida = ?',
                        f'{dia}_SalidaRefri = ?',
                        f'{dia}_EntradaRefri = ?',
                    ]
                )
                params_up.extend(valores_dia[base : base + 5])
            params_up.extend([hid, company_s])
            sql_up = f"UPDATE Horarios SET {', '.join(set_parts)} WHERE IdHorario = ? AND Company = ?"
            cursor.execute(sql_up, params_up)
            if cursor.rowcount == 0:
                cursor.close()
                conn.close()
                return False, 'No se encontró el horario o no pertenece a la compañía.', None
            conn.commit()
            cursor.close()
            conn.close()
            return True, None, hid

        columnas = ['NombreHorario', 'ToleranciaMinutos'] + cols_dia + ['Company']
        placeholders = ', '.join(['?'] * len(columnas))
        sql_ins = f"INSERT INTO Horarios ({', '.join(columnas)}) VALUES ({placeholders})"
        params_ins = [nombre_s, tol] + valores_dia + [company_s]
        cursor.execute(sql_ins, params_ins)
        cursor.execute("SELECT CAST(SCOPE_IDENTITY() AS int)")
        row_id = cursor.fetchone()
        new_id = int(row_id[0]) if row_id and row_id[0] is not None else None
        conn.commit()
        cursor.close()
        conn.close()
        return True, None, new_id
    except Exception as e:
        print(f"Error al guardar horario: {e}")
        return False, str(e), None


def get_tipos_documentos():
    """Obtiene la lista de tipos de documentos desde PR_tipodocWeb"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT Tipodocumento, name FROM PR_tipodocWeb")
        
        results = [{'Tipodocumento': row[0], 'name': row[1]} for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_tipos_documentos: {e}")
        return []


def get_filtro_periodos(company):
    """Obtiene la lista de períodos disponibles ejecutando sp_pr_FiltroPeriodos_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_FiltroPeriodos_web @cia=?", (company,))
        
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_filtro_periodos: {e}")
        return []


def get_documentos_personales(company, person, tipodoc='BOL'):
    """Obtiene la lista de documentos disponibles (boletas) para el empleado.
    
    Args:
        company: ID de la compañía
        person: ID de la persona
        tipodoc: Tipo de documento (por defecto 'BOL')
    """
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        
        cursor.execute("EXEC sp_pr_listadocumentos_web @cia=?, @person=?, @tipodoc=?", 
                      (company, person, tipodoc))
        
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_documentos_personales: {e}")
        return []


def actualizar_descarga(company, person, tipodocumento, prperiod):
    """Actualiza la fecha de descarga del documento ejecutando sp_pr_Actualizardescarga_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_Actualizardescarga_web @cia=?, @person=?, @tipodocumento=?, @prperiod=?", 
                      (company, person, tipodocumento, prperiod))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error en actualizar_descarga: {e}")
        return False


def registrar_comprobante_web(company, payrolltype, processtype, period, person, userid, filename, tipo='BOL'):
    """Registra el comprobante generado en PR_DocumentPerson. SP sp_pr_registrarcomprobantes_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_registrarcomprobantes_web @cia=?, @payrolltype=?, @processtype=?, @period=?, @person=?, @userid=?, @filename=?, @tipo=?",
            (company, payrolltype, processtype, period, person, userid, filename, tipo)
        )
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error en registrar_comprobante_web: {e}")
        return False


def get_envio_comprobantes(company, tipodoc='BOL', prperiod=None):
    """Obtiene la lista de envío de comprobantes ejecutando sp_pr_enviocomprobantes_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        
        # El SP requiere el parámetro @prperiod
        # Si no se proporciona, se pasa None (el SP debería manejarlo o necesitará modificación)
        prperiod_value = prperiod if prperiod and prperiod.strip() else None
        
        cursor.execute("EXEC sp_pr_enviocomprobantes_web @cia=?, @tipodoc=?, @prperiod=?", 
                      (company, tipodoc, prperiod_value))
        
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_envio_comprobantes: {e}")
        return []


def get_reporte_descargas(company, tipodoc='BOL', prperiod=None):
    """Obtiene el reporte de descargas ejecutando sp_pr_reportedescargas_web.
    Devuelve: DNI, Nombre, Correo, NombreArchivo, FechaGenera, Primeradescarga.
    """
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        prperiod_value = prperiod if prperiod and prperiod.strip() else None
        cursor.execute(
            "EXEC sp_pr_reportedescargas_web @cia=?, @tipodoc=?, @prperiod=?",
            (company, tipodoc, prperiod_value)
        )
        columns = [column[0] for column in cursor.description]
        results = []
        for row in cursor.fetchall():
            d = dict(zip(columns, row))
            # Asegurar que 'Nombre' exista para la vista (el SP devuelve SY_Person.Name as Nombre)
            if 'Nombre' not in d or d.get('Nombre') is None or str(d.get('Nombre', '')).strip() == '':
                d['Nombre'] = d.get('Name') or d.get('nombre') or ''
            results.append(d)
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_reporte_descargas: {e}")
        return []


def actualizar_fecha_envio_db(company, person, tipodoc):
    """Actualiza la fecha de envío en PR_DocumentPerson"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        # Usamos GETDATE() para registrar el momento exacto del envío
        query = "UPDATE PR_DocumentPerson SET fechaenvio = GETDATE() WHERE Company = ? AND Person = ? AND Tipodocumento = ?"
        cursor.execute(query, (company, person, tipodoc))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error actualizando fecha de envío: {e}")
        return False


def registrar_solicitud_permiso(company, person, userid, controlyear, fechaini, fechafin, comentario):
    """Registra una solicitud de permiso ejecutando sp_pr_RegistrarSolicitudPermiso_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_RegistrarSolicitudPermiso_web @cia=?, @person=?, @userid=?, @controlyear=?, @fechaini=?, @fechaFin=?, @comentario=?", 
                      (company, person, userid, controlyear, fechaini, fechafin, comentario))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error en registrar_solicitud_permiso: {e}")
        return False


def get_max_dias_vacaciones(company):
    """Obtiene el máximo de días de vacaciones desde PR_mapping2 para la company (@cia)."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT ISNULL(DiasVacaciones,0) FROM PR_mapping2 WHERE company = ?", (company,))
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row is not None and row[0] is not None:
            return int(row[0])
        return 30
    except Exception as e:
        print(f"Error en get_max_dias_vacaciones: {e}")
        return 30


def get_constancia_datos(company, person):
    """
    Obtiene los datos para la constancia de trabajo ejecutando sp_pr_constanciatrabajo_web
    """
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_constanciatrabajo_web @person=?, @cia=?", (person, company))
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            return None
        columns = [column[0] for column in cursor.description]
        result = dict(zip(columns, row))
        cursor.close()
        conn.close()
        return result
    except Exception as e:
        print(f"Error en get_constancia_datos: {e}")
        return None


def get_lista_solicitudes_permiso(company, person):
    """Obtiene la lista de solicitudes de permiso ejecutando sp_pr_ListarSolicitudPermiso_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_ListarSolicitudPermiso_web @cia=?, @person=?", (company, person))
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_lista_solicitudes_permiso: {e}")
        return []


def get_aprobacion_solicitudes_pendientes(company, name=None, estado='P'):
    """Obtiene la lista de solicitudes ejecutando sp_pr_AprobarSolicitudesPendientes_web.
    name: filtro opcional por nombre. estado: 'P' Pendiente, 'A' Aprobado, 'T' Todos. Por defecto P."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        name_param = (name or '').strip()
        estado_param = (estado or 'P').strip().upper()
        if estado_param not in ('P', 'A', 'T'):
            estado_param = 'P'
        cursor.execute(
            "EXEC sp_pr_AprobarSolicitudesPendientes_web @cia=?, @name=?, @estado=?",
            (company, name_param, estado_param)
        )
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error en get_aprobacion_solicitudes_pendientes: {e}")
        return []


def eliminar_solicitud_permiso(company, person, line):
    """Elimina una solicitud de permiso ejecutando sp_pr_EliminarSolicitudPermiso_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_EliminarSolicitudPermiso_web @cia=?, @person=?, @line=?",
            (company, person, int(line))
        )
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error en eliminar_solicitud_permiso: {e}")
        return False


def aprobar_solicitud_web(company, person, controlyear, line, userid):
    """Aprueba una solicitud ejecutando sp_pr_AprobarSolicitud_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_AprobarSolicitud_web @cia=?, @person=?, @controlyear=?, @line=?, @userid=?",
            (company, person, str(controlyear), int(line), userid)
        )
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error en aprobar_solicitud_web: {e}")
        return False


def get_boleta_cabecera(company, process, payrolltype, period, person):
    """Ejecuta sp_pr_generarboleta_web para datos del encabezado"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_generarboleta_web @cia=?, @process=?, @payrolltype=?, @period=?, @person=?",
            (company, process, payrolltype, period, person)
        )
        columns = [column[0] for column in cursor.description]
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        return dict(zip(columns, row)) if row else None
    except Exception as e:
        print(f"Error get_boleta_cabecera: {e}")
        return None


def get_boleta_conceptos(company, process, payrolltype, period, person, tipo):
    """
    Ejecuta los SPs de detalle según el tipo:
    tipo='I': Ingresos, tipo='D': Descuentos, tipo='A': Aportes
    """
    sp_map = {
        'I': 'sp_pr_detalleboletaingresos_web',
        'D': 'sp_pr_detalleboletadescuentos_web',
        'A': 'sp_pr_detalleboletaaportes_web'
    }
    sp_name = sp_map.get(tipo)
    if not sp_name:
        return []
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            f"EXEC {sp_name} @cia=?, @process=?, @payrolltype=?, @period=?, @person=?",
            (company, process, payrolltype, period, person)
        )
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error get_boleta_conceptos ({tipo}): {e}")
        return []


def get_selector_planillas(company):
    """Obtiene tipos de planilla para el selector. SP sp_pr_selectorplanillas_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_pr_selectorplanillas_web @cia=?", (company,))
        if cursor.description is None:
            cursor.close()
            conn.close()
            return []
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error get_selector_planillas: {e}")
        return []


def get_selector_procesos(company, payrolltype):
    """Obtiene procesos para el selector. SP sp_pr_selectorprocesos_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_selectorprocesos_web @cia=?, @payrolltype=?",
            (company, payrolltype)
        )
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error get_selector_procesos: {e}")
        return []


def get_selector_periodos(company, payrolltype, processtype):
    """Obtiene periodos para el selector. SP sp_pr_selectorperiodos_web"""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_pr_selectorperiodos_web @cia=?, @payrolltype=?, @processtype=?",
            (company, payrolltype, processtype)
        )
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error get_selector_periodos: {e}")
        return []


def get_listado_generar_boletas(company, payrolltype, processtype, period, name=None):
    """Obtiene listado para generar boletas. SP sp_pr_listadogenerarboletas_web (filtro opcional @name)."""
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        name_val = (name or '').strip() if name is not None else ''
        cursor.execute(
            "EXEC sp_pr_listadogenerarboletas_web @cia=?, @payrolltype=?, @processtype=?, @period=?, @name=?",
            (company, payrolltype, processtype, period, name_val)
        )
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        cursor.close()
        conn.close()
        return results
    except Exception as e:
        print(f"Error get_listado_generar_boletas: {e}")
        return []

