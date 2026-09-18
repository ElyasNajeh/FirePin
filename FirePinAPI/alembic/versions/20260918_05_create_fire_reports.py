"""create fire reports

Revision ID: 20260918_05
Revises: 20260918_04
Create Date: 2026-09-18
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "20260918_05"
down_revision: str | None = "20260918_04"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "fire_reports",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("reporter_id", sa.Integer(), nullable=False),
        sa.Column("municipality_id", sa.Integer(), nullable=False),
        sa.Column("assigned_volunteer_id", sa.Integer(), nullable=True),
        sa.Column("latitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column("longitude", sa.Numeric(precision=9, scale=6), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            server_default=sa.text("'pending'"),
            nullable=False,
        ),
        sa.Column(
            "reported_at",
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
            "(status = 'pending' AND assigned_volunteer_id IS NULL) OR "
            "(status IN ('assigned', 'resolved') "
            "AND assigned_volunteer_id IS NOT NULL)",
            name="ck_fire_reports_assignment_state",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'assigned', 'resolved')",
            name="ck_fire_reports_status",
        ),
        sa.ForeignKeyConstraint(
            ["assigned_volunteer_id"],
            ["volunteers.id"],
        ),
        sa.ForeignKeyConstraint(["municipality_id"], ["municipalities.id"]),
        sa.ForeignKeyConstraint(["reporter_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_fire_reports_assigned_volunteer_id",
        "fire_reports",
        ["assigned_volunteer_id"],
        unique=False,
    )
    op.create_index(
        "ix_fire_reports_municipality_status",
        "fire_reports",
        ["municipality_id", "status"],
        unique=False,
    )
    op.create_index(
        "ix_fire_reports_reporter_status",
        "fire_reports",
        ["reporter_id", "status"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_fire_reports_reporter_status",
        table_name="fire_reports",
    )
    op.drop_index(
        "ix_fire_reports_municipality_status",
        table_name="fire_reports",
    )
    op.drop_index(
        "ix_fire_reports_assigned_volunteer_id",
        table_name="fire_reports",
    )
    op.drop_table("fire_reports")
