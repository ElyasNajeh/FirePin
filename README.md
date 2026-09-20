# 🔥 FirePin

FirePin is a mobile fire detection and alert system designed to provide fast and accurate fire notifications.

The system receives fire detection events from connected sensors, identifies the registered location of the detected fire, and sends real-time alerts to users through the FirePin mobile application.

## 👥 Team

- **Elyas Ihmud** — Backend Developer

- **Khaled Hamayel** — Backend Developer

- **Ramzi Abu Falah** — Frontend Developer

- **Hareth Shoman** — Frontend Developer

- **Adel Khair** — QA

## ✨ Features

- Receive fire detection events from connected sensors.

- Identify the registered location of the detected fire.

- Send real-time fire alerts to users.

- Display fire location and related information.

- Store and track fire events.

- Support Android and iOS through a single mobile application.

## 🛠 Technologies & Tools

### Mobile

- **Flutter** — Cross-platform mobile development for Android and iOS.

- **Dart** — Programming language used to build the Flutter application.

### Backend

- **FastAPI** — Lightweight and high-performance REST API framework.

- **Python** — Backend programming language.

- **SQLAlchemy** — ORM for database operations.

- **AsyncPG** — Asynchronous PostgreSQL driver.

- **Alembic** — Database schema migrations.

- **Pydantic** — Request, response, and data validation.

### Database

- **PostgreSQL** — Stores sensors, locations, fire events, and application data.

- **Adminer** — Simple web interface for database management.

### Development & Deployment

- **Docker** — Provides an isolated and consistent backend environment.

- **Docker Compose** — Runs the API, PostgreSQL, and Adminer together.

- **Git & GitHub** — Version control and team collaboration.

## 🔌 Ports

| Service | Port |
| --- | ---: |
| FastAPI | `8000` |
| PostgreSQL | `5432` |
| Adminer | `8080` |

> Flutter runs directly on a connected device or emulator and is not containerized.

## 🚀 Getting Started

### Prerequisites

Make sure the following are installed:

- Git

- Docker & Docker Compose

- Flutter SDK

- Android Studio or another supported Android/iOS development environment

### 1. Clone the Repository

```bash
git clone <repository-url>
cd FirePin
```

### 2. Configure Environment Variables

Create `.env` from the provided `.env.example`:

**Linux / macOS / Git Bash**

```bash
cp .env.example .env
```

**Windows PowerShell**

```powershell
Copy-Item .env.example .env
```

Then update the values inside `.env` if needed.

Before running the project, make sure to get the required private configuration from the team:

- Set the provided `SECRET_KEY` in `.env`.
- Set the provided `FIREBASE_CREDENTIALS_PATH` in `.env`.
- Get the `FirePinAPI/secrets` folder containing the Firebase credentials file and place it in the same path in the project.

These values and files are private and are not included in the repository.

### 3. Start the Backend

Build and start FastAPI, PostgreSQL, and Adminer:

```bash
docker compose up -d --build
```

Check the running containers:

```bash
docker compose ps
```

The backend services will be available at:

| Service | URL |
| --- | --- |
| FastAPI | `http://localhost:8000` |
| API Documentation | `http://localhost:8000/docs` |
| Adminer | `http://localhost:8080` |

Database migrations are automatically applied when the API container starts.

To stop the backend:

```bash
docker compose down
```

### 4. Start the Mobile Application

Open the Flutter project:

```bash
cd FirePinUI
```

Install dependencies:

```bash
flutter pub get
```

Verify the Flutter environment:

```bash
flutter doctor
```

Check available devices:

```bash
flutter devices
```

Run FirePin:

```bash
flutter run
```

The application will start on the selected connected device or emulator.

## 📁 Project Structure

```text
FirePin/
├── FirePinAPI/              # FastAPI backend
├── FirePinUI/               # Flutter mobile application
├── .env.example             # Environment variables template
├── docker-compose.yml       # Development services
├── docker-compose.prod.yml  # Production services
└── README.md
```