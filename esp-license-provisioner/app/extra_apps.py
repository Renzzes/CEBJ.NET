"""Entry points for seller generator / buyer replacement apps."""
from app.license_generator_app import main as generator_main
from app.buyer_replacement_app import main as buyer_main

__all__ = ["generator_main", "buyer_main"]
