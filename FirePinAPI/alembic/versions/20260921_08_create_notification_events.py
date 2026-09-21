"""create persistent notification events

Revision ID: 20260921_08
Revises: 20260918_07
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "20260921_08"
down_revision: str | None = "20260918_07"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "notification_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("recipient_user_id", sa.Integer(), nullable=True),
        sa.Column("recipient_municipality_id", sa.Integer(), nullable=True),
        sa.Column("fire_report_id", sa.Integer(), nullable=False),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("body", sa.String(length=500), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "(recipient_user_id IS NOT NULL AND recipient_municipality_id IS NULL) "
            "OR (recipient_user_id IS NULL AND recipient_municipality_id IS NOT NULL)",
            name="ck_notification_events_one_recipient",
        ),
        sa.ForeignKeyConstraint(
            ["recipient_user_id"], ["users.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["recipient_municipality_id"],
            ["municipalities.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["fire_report_id"], ["fire_reports.id"], ondelete="CASCADE"
        ),
    )
    op.create_index(
        "ix_notification_events_user_created",
        "notification_events",
        ["recipient_user_id", "id"],
    )
    op.create_index(
        "ix_notification_events_municipality_created",
        "notification_events",
        ["recipient_municipality_id", "id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_notification_events_municipality_created",
        table_name="notification_events",
    )
    op.drop_index(
        "ix_notification_events_user_created", table_name="notification_events"
    )
    op.drop_table("notification_events")
