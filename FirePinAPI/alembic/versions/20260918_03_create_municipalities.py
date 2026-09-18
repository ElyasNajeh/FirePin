"""create municipalities and municipality sessions

Revision ID: 20260918_03
Revises: 20260918_02
Create Date: 2026-09-18
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "20260918_03"
down_revision: str | None = "20260918_02"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "municipalities",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("latitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column("longitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column(
            "is_active",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_municipalities_email"),
        "municipalities",
        ["email"],
        unique=True,
    )
    op.create_index(
        op.f("ix_municipalities_name"),
        "municipalities",
        ["name"],
        unique=True,
    )

    op.create_table(
        "municipality_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("municipality_id", sa.Integer(), nullable=False),
        sa.Column("refresh_token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["municipality_id"],
            ["municipalities.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_municipality_sessions_municipality_id"),
        "municipality_sessions",
        ["municipality_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_municipality_sessions_refresh_token_hash"),
        "municipality_sessions",
        ["refresh_token_hash"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_municipality_sessions_refresh_token_hash"),
        table_name="municipality_sessions",
    )
    op.drop_index(
        op.f("ix_municipality_sessions_municipality_id"),
        table_name="municipality_sessions",
    )
    op.drop_table("municipality_sessions")

    op.drop_index(op.f("ix_municipalities_name"), table_name="municipalities")
    op.drop_index(op.f("ix_municipalities_email"), table_name="municipalities")
    op.drop_table("municipalities")
