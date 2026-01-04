from sqlalchemy.schema import CreateTable, CreateIndex
from sqlalchemy.dialects import postgresql

import models  # noqa: F401
from database import Base


def main() -> None:
    dialect = postgresql.dialect()

    tables = [Base.metadata.tables[k] for k in sorted(Base.metadata.tables.keys())]

    stmts: list[str] = []
    for t in tables:
        stmts.append(str(CreateTable(t).compile(dialect=dialect)).rstrip() + ";")

    for t in tables:
        for idx in sorted(t.indexes, key=lambda i: i.name or ""):
            stmts.append(str(CreateIndex(idx).compile(dialect=dialect)).rstrip() + ";")

    sql = "\n\n".join(stmts) + "\n"
    with open("schema_postgres.sql", "w", encoding="utf-8") as f:
        f.write(sql)

    print("Wrote schema_postgres.sql")


if __name__ == "__main__":
    main()
