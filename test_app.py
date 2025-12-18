import app


def test_calculate_next_charge_weekly():
    assert app.calculate_next_charge("2025-01-01", "weekly") == "2025-01-08"


def test_calculate_next_charge_monthly():
    # В текущей реализации monthly = +30 дней
    assert app.calculate_next_charge("2025-01-01", "monthly") == "2025-01-31"


def test_calculate_next_charge_yearly():
    assert app.calculate_next_charge("2025-01-01", "yearly") == "2026-01-01"
