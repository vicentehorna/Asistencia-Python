"""
Pobla hm_atilio2 con trabajadores BGT activos de hm_safari (omitir DNIs existentes)
y genera marcas aleatorias en RegistroAsistencia para junio 2026.
"""
from __future__ import annotations

import random
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")
import database as db

CIA = "BGT"
ID_HORARIO_ADMIN = 1
FECHA_INI = date(2026, 6, 1)
FECHA_FIN = date(2026, 6, 30)
ID_TRABAJADOR_FK = 1
XUSER = "SEED_SAFARI"
RANDOM_SEED = 20260618

# Probabilidad de falta (sin marcas ese día)
PROB_FALTA = 0.12

# Horario ADMINISTRATIVO
H_ENTRADA = time(8, 30)
H_SALIDA_REF = time(13, 0)
H_ENTRADA_REF = time(14, 0)
H_SALIDA = time(17, 30)


def weekdays_in_range(d0: date, d1: date) -> list[date]:
    out = []
    d = d0
    while d <= d1:
        if d.weekday() < 5:  # Lun-Vie
            out.append(d)
        d += timedelta(days=1)
    return out


def combine(d: date, t: time, minute_offset: int = 0, second: int | None = None) -> datetime:
    base = datetime.combine(d, t) + timedelta(minutes=minute_offset)
    if second is None:
        second = random.randint(0, 59)
    return base.replace(second=second, microsecond=0)


def gen_day_marks(d: date) -> list[datetime]:
    """4 marcas cercanas al horario, con variación para tardanza / tiempo extra."""
    # Entrada: a veces temprano (-10..0), a menudo tarde (1..35) para tardanzas
    if random.random() < 0.35:
        off_in = random.randint(-12, 0)
    else:
        off_in = random.randint(1, 35)

    # Salida refrigerio ~13:00 ± 8 min
    off_out_ref = random.randint(-5, 10)
    # Retorno refrigerio ~14:00 ± 10 min (a veces tarde)
    if random.random() < 0.4:
        off_in_ref = random.randint(1, 18)
    else:
        off_in_ref = random.randint(-5, 5)

    # Salida: a veces temprano, a menudo tarde (tiempo extra)
    if random.random() < 0.30:
        off_out = random.randint(-20, 0)
    else:
        off_out = random.randint(5, 75)

    marks = [
        combine(d, H_ENTRADA, off_in),
        combine(d, H_SALIDA_REF, off_out_ref),
        combine(d, H_ENTRADA_REF, off_in_ref),
        combine(d, H_SALIDA, off_out),
    ]
    marks.sort()
    return marks


def main() -> None:
    random.seed(RANDOM_SEED)
    days = weekdays_in_range(FECHA_INI, FECHA_FIN)
    print(f"Días laborables junio 2026: {len(days)} ({days[0]} .. {days[-1]})")

    # --- Fuente: hm_safari ---
    conn_s = db.DatabaseConfig.get_connection(database="hm_safari")
    cur_s = conn_s.cursor()
    cur_s.execute(
        """
        SELECT LTRIM(RTRIM(e.Person)) AS Person,
               LTRIM(RTRIM(ISNULL(p.Name, e.Person))) AS Name
        FROM PR_Employee e
        INNER JOIN SY_Person p ON p.Person = e.Person
        WHERE e.Company = ?
          AND e.Status = 'N'
        ORDER BY p.Name
        """,
        (CIA,),
    )
    safari_workers = [(str(r[0]).strip(), str(r[1]).strip()) for r in cur_s.fetchall()]
    cur_s.close()
    conn_s.close()
    print(f"Safari BGT activos: {len(safari_workers)}")

    # --- Destino: hm_atilio2 ---
    conn = db.DatabaseConfig.get_connection(database="hm_atilio2")
    cur = conn.cursor()

    cur.execute("SELECT LTRIM(RTRIM(Person)) FROM SY_Person")
    existing_persons = {str(r[0]).strip() for r in cur.fetchall()}
    cur.execute("SELECT LTRIM(RTRIM(Person)) FROM PR_Employee WHERE Company = ?", (CIA,))
    existing_emp = {str(r[0]).strip() for r in cur.fetchall()}
    existing = existing_persons | existing_emp
    print(f"DNIs ya en hm_atilio2 (Person o Employee BGT): {len(existing)}")

    nuevos = [(p, n) for p, n in safari_workers if p not in existing]
    omitidos = len(safari_workers) - len(nuevos)
    print(f"A insertar: {len(nuevos)} | Omitidos (ya existen): {omitidos}")

    if not nuevos:
        print("No hay trabajadores nuevos. Abortando generación de marcas.")
        cur.close()
        conn.close()
        return

    now = datetime.now().replace(microsecond=0)

    # Insert SY_Person
    person_rows = []
    for person, name in nuevos:
        pin = person[-4:] if len(person) >= 4 else person
        person_rows.append(
            (
                person[:20],
                name[:100],
                "N",  # FlagSUNAT5
                "N",  # istrainer
                "N",  # isrecruiter
                "N",  # issupervisor
                "N",  # FlagLockCA
                "L",  # LicenseCondition
                pin[:10],  # pinAcceso
            )
        )

    cur.fast_executemany = True
    cur.executemany(
        """
        INSERT INTO SY_Person (
            Person, Name, FlagSUNAT5, istrainer, isrecruiter, issupervisor,
            FlagLockCA, LicenseCondition, pinAcceso
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        person_rows,
    )
    print(f"SY_Person insertados: {len(person_rows)}")

    # Insert PR_Employee
    emp_rows = [
        (
            person[:20],
            CIA,
            "N",  # Status activo
            "N",  # confirmcessation
            FECHA_INI,  # EntryDate aproximada
        )
        for person, _ in nuevos
    ]
    cur.executemany(
        """
        INSERT INTO PR_Employee (Person, Company, Status, confirmcessation, EntryDate)
        VALUES (?, ?, ?, ?, ?)
        """,
        emp_rows,
    )
    print(f"PR_Employee insertados: {len(emp_rows)}")

    # AsignacionHorarios ADMINISTRATIVO
    asig_rows = [
        (
            person[:20],
            CIA,
            ID_HORARIO_ADMIN,
            FECHA_INI,
            date(2026, 12, 31),
            now,
            XUSER,
            now,
        )
        for person, _ in nuevos
    ]
    cur.executemany(
        """
        INSERT INTO AsignacionHorarios (
            Person, Company, IdHorario, FechaInicio, FechaFin,
            FechaRegistro, XLastUser, XLastDate
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        asig_rows,
    )
    print(f"AsignacionHorarios (ADMINISTRATIVO): {len(asig_rows)}")

    # Marcas junio 2026
    mark_rows = []
    faltas = 0
    dias_con_marca = 0
    for person, _ in nuevos:
        for d in days:
            if random.random() < PROB_FALTA:
                faltas += 1
                continue
            dias_con_marca += 1
            for fh in gen_day_marks(d):
                mark_rows.append(
                    (
                        ID_TRABAJADOR_FK,
                        fh,
                        person[:20],
                        CIA,
                        XUSER,
                        now,
                        "N",  # flagmanual
                        "A",  # estado
                    )
                )

    print(f"Person-días con marca: {dias_con_marca} | Person-días falta: {faltas}")
    print(f"Marcas a insertar: {len(mark_rows)}")

    # Insert en lotes
    batch = 2000
    sql_mark = """
        INSERT INTO RegistroAsistencia (
            IdTrabajador, FechaHoraIngreso, Person, company,
            xlastuser, xlastdate, flagmanual, estado
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """
    for i in range(0, len(mark_rows), batch):
        chunk = mark_rows[i : i + batch]
        cur.executemany(sql_mark, chunk)
        print(f"  insertadas {min(i + batch, len(mark_rows))}/{len(mark_rows)}")

    conn.commit()

    # Verificación (usar datetime: ODBC antiguo no bindéa date de Python)
    dt_ini = datetime.combine(FECHA_INI, time.min)
    dt_fin_excl = datetime.combine(FECHA_FIN + timedelta(days=1), time.min)

    cur.execute(
        """
        SELECT COUNT(*)
        FROM RegistroAsistencia R
        INNER JOIN SY_Person P ON R.Person = P.Person
        INNER JOIN PR_Employee E ON P.Person = E.Person AND E.Company = ?
        WHERE R.estado = 'A'
          AND R.xlastuser = ?
          AND R.FechaHoraIngreso >= ?
          AND R.FechaHoraIngreso < ?
        """,
        (CIA, XUSER, dt_ini, dt_fin_excl),
    )
    visible = cur.fetchone()[0]
    print(f"Marcas visibles en Gestión (seed {XUSER}): {visible}")

    cur.execute(
        """
        SELECT COUNT(DISTINCT R.Person)
        FROM RegistroAsistencia R
        WHERE R.xlastuser = ?
          AND R.FechaHoraIngreso >= ?
          AND R.FechaHoraIngreso < ?
        """,
        (XUSER, dt_ini, dt_fin_excl),
    )
    persons_with_marks = cur.fetchone()[0]
    print(f"Trabajadores nuevos con al menos 1 marca: {persons_with_marks}")

    cur.execute(
        """
        SELECT TOP 5 P.Person, P.Name, COUNT(*) AS marcas
        FROM RegistroAsistencia R
        INNER JOIN SY_Person P ON R.Person = P.Person
        WHERE R.xlastuser = ?
          AND R.FechaHoraIngreso >= ?
          AND R.FechaHoraIngreso < ?
        GROUP BY P.Person, P.Name
        ORDER BY P.Name
        """,
        (XUSER, dt_ini, dt_fin_excl),
    )
    print("Muestra:")
    for r in cur.fetchall():
        print(" ", r)

    # Test SP
    cur.execute(
        "EXEC dbo.sp_pr_listadomarcas_web @cia=?, @Fechainicio=?, @FechaFin=?, @person=?",
        (CIA, datetime(2026, 6, 1), datetime(2026, 6, 30), "0"),
    )
    sp_rows = cur.fetchall()
    print(f"sp_pr_listadomarcas_web junio 2026 (todos): {len(sp_rows)} filas")

    cur.close()
    conn.close()
    print("OK")


if __name__ == "__main__":
    main()
