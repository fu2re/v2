"""CLI: `uv run balance-admin serve` из tools/balance_admin."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(prog="balance-admin",
                                     description="Балансовая админка BEATROOT")
    sub = parser.add_subparsers(dest="command", required=True)

    serve = sub.add_parser("serve", help="поднять локальный редактор")
    serve.add_argument("--port", type=int, default=8765)
    serve.add_argument("--root", type=Path,
                       default=Path(__file__).resolve().parents[3],
                       help="корень проекта (по умолчанию — репозиторий)")

    check = sub.add_parser("check", help="прогнать валидатор без сервера")
    check.add_argument("--root", type=Path,
                       default=Path(__file__).resolve().parents[3])

    args = parser.parse_args()
    if args.command == "serve":
        _serve(args.root.resolve(), args.port)
    elif args.command == "check":
        raise SystemExit(_check(args.root.resolve()))


def _serve(root: Path, port: int) -> None:
    import uvicorn

    from .app import create_app

    app = create_app(root)
    print(f"Балансовая админка: http://127.0.0.1:{port}  (root: {root})")
    # Только loopback: это локальный инструмент без авторизации,
    # и слушать сеть ему незачем
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")


def _check(root: Path) -> int:
    from . import configs, validator

    tables = {c["name"]: configs.read_config(root, c["name"])
              for c in configs.list_configs(root)}
    errors, warnings = validator.validate(root, tables)
    for line in errors:
        print(f"ОШИБКА: {line}")
    for line in warnings:
        print(f"предупреждение: {line}")
    if not errors and not warnings:
        print("Чисто.")
    return 1 if errors else 0


if __name__ == "__main__":
    main()
