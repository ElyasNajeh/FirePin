"""create device tokens

Revision ID: 20260918_07
Revises: 20260918_06
Create Date: 2026-09-18
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "20260918_07"
down_revision: str | None = "20260918_06"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "device_tokens",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("municipality_id", sa.Integer(), nullable=True),
        sa.Column("token", sa.String(length=500), nullable=False),
        sa.Column("platform", sa.String(length=20), nullable=False),
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
        sa.CheckConstraint(
            "(user_id IS NOT NULL AND municipality_id IS NULL) OR "
            "(user_id IS NULL AND municipality_id IS NOT NULL)",
            name="ck_device_tokens_exactly_one_owner",
        ),
        sa.CheckConstraint(
            "platform IN ('android', 'ios')",
            name="ck_device_tokens_platform",
        ),
        sa.ForeignKeyConstraint(
            ["municipality_id"],
            ["municipalities.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token"),
    )
    op.create_index(
        op.f("ix_device_tokens_municipality_id"),
        "device_tokens",
        ["municipality_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_device_tokens_user_id"),
        "device_tokens",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        op.f("ix_device_tokens_user_id"),
        table_name="device_tokens",
    )
    op.drop_index(
        op.f("ix_device_tokens_municipality_id"),
        table_name="device_tokens",
    )
    op.drop_table("device_tokens")
