"""Ejecuta archivos .sql en SQL Server (lotes separados por GO)."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv()

from database import DatabaseConfig  # noqa: E402


def split_batches(text: str) -> list[str]:
    return [
        batch.strip()
        for batch in re.split(r"^\s*GO\s*$", text, flags=re.MULTILINE | re.IGNORECASE)
        if batch.strip()
    ]


def proc_exists(cursor, name: str) -> bool:
    cursor.execute("SELECT 1 FROM sys.procedures WHERE name = ?", (name,))
    return cursor.fetchone() is not None


def prepare_sp_text(text: str, proc_name: str, exists: bool) -> str:
    if exists:
        return text
    return re.sub(r"ALTER\s+PROCEDURE", "CREATE PROCEDURE", text, count=1, flags=re.IGNORECASE)


def run_file(cursor, path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if path.name.startswith("sp_"):
        match = re.search(r"\[dbo\]\.\[(\w+)\]", text, re.IGNORECASE)
        if match:
            proc_name = match.group(1)
            exists = proc_exists(cursor, proc_name)
            if exists:
                cursor.execute(f"DROP PROCEDURE [dbo].[{proc_name}]")
                print(f"   {proc_name}: DROP previo")
            text = prepare_sp_text(text, proc_name, exists=False)

    batches = split_batches(text)
    print(f"==> {path} ({len(batches)} lotes)")
    for index, batch in enumerate(batches, 1):
        cursor.execute(batch)
        print(f"   lote {index}: OK")


def main(argv: list[str]) -> int:
    paths = [ROOT / arg for arg in argv] if argv else []
    if not paths:
        print("Uso: python scripts/run_sql_files.py <archivo.sql> [...]")
        return 1

    conn = DatabaseConfig.get_connection()
    conn.autocommit = True
    cursor = conn.cursor()
    try:
        for path in paths:
            if not path.exists():
                print(f"ERROR: no existe {path}")
                return 1
            run_file(cursor, path)
    finally:
        cursor.close()
        conn.close()

    print("Listo.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
