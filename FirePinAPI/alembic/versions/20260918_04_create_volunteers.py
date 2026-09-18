"""create volunteer applications and volunteers

Revision ID: 20260918_04
Revises: 20260918_03
Create Date: 2026-09-18
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "20260918_04"
down_revision: str | None = "20260918_03"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "volunteer_applications",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("municipality_id", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            server_default=sa.text("'pending'"),
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
        sa.CheckConstraint(
            "status IN ('pending', 'accepted', 'rejected')",
            name="ck_volunteer_applications_status",
        ),
        sa.ForeignKeyConstraint(["municipality_id"], ["municipalities.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_volunteer_applications_municipality_status",
        "volunteer_applications",
        ["municipality_id", "status"],
        unique=False,
    )
    op.create_index(
        "ix_volunteer_applications_user_id",
        "volunteer_applications",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "uq_volunteer_applications_user_pending",
        "volunteer_applications",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("status = 'pending'"),
    )

    op.create_table(
        "volunteers",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("municipality_id", sa.Integer(), nullable=False),
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
        sa.ForeignKeyConstraint(["municipality_id"], ["municipalities.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_volunteers_municipality_id"),
        "volunteers",
        ["municipality_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_volunteers_user_id"),
        "volunteers",
        ["user_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_volunteers_user_id"), table_name="volunteers")
    op.drop_index(
        op.f("ix_volunteers_municipality_id"),
        table_name="volunteers",
    )
    op.drop_table("volunteers")

    op.drop_index(
        "uq_volunteer_applications_user_pending",
        table_name="volunteer_applications",
    )
    op.drop_index(
        "ix_volunteer_applications_user_id",
        table_name="volunteer_applications",
    )
    op.drop_index(
        "ix_volunteer_applications_municipality_status",
        table_name="volunteer_applications",
    )
    op.drop_table("volunteer_applications")
