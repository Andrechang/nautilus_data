FROM python:3.11-slim as base
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    POETRY_VERSION=1.6.1 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_CREATE=false \
    POETRY_NO_INTERACTION=1 \
    PYSETUP_PATH="/opt/pysetup"
ENV PATH="/root/.cargo/bin:$POETRY_HOME/bin:$PATH"
WORKDIR $PYSETUP_PATH

FROM base as builder

# Install build deps
RUN apt-get update && apt-get install -y curl clang git libssl-dev make pkg-config

# Install Rust stable
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y

# Install poetry
RUN curl -sSL https://install.python-poetry.org | python3 -

# Install project (revert to this up to 'base as application', once the data catalog is stable)
# COPY pyproject.toml poetry.lock ./
# RUN poetry install --only main
# COPY . ./
# RUN poetry install

# Install package requirements (split step and with --no-root to enable caching)
COPY poetry.lock pyproject.toml build.py ./
RUN poetry install --no-root --only main

# Build nautilus_trader
COPY nautilus_core ./nautilus_core
RUN (cd nautilus_core && cargo build --release)

COPY nautilus_trader ./nautilus_trader
COPY README.md ./
RUN poetry install --only main --all-extras
RUN poetry build -f wheel
RUN python -m pip install ./dist/*whl --force
RUN find /usr/local/lib/python3.11/site-packages -name "*.pyc" -exec rm -f {} \;

FROM base as application

ENV CATALOG_PATH=/catalog

# Copy python environment from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY ./scripts $PYSETUP_PATH/scripts

# Generate data catalog
RUN python -m scripts.hist_data_to_catalog

# Run backtest to generate data
RUN python -m scripts.example_backtest
