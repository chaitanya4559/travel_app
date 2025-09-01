# ✈️ WanderLog – Your Offline-First Travel Companion

📝 A modern, cross-platform travel journal built with Flutter and Supabase, designed to capture your adventures with photos, voice notes, and AI-powered insights, even without an internet connection.

---
## 🎯 Objective

The goal of **WanderLog** is to provide a seamless and reliable way for travelers to document their journeys with rich media and intelligent features, ensuring data is always safe and accessible, online or offline.

---
## ✨ Features

### 🔐 Secure Authentication
* **Social Login:** Simple and secure user authentication using providers like Google or Apple via Supabase Auth.

### 📓 Rich Journal Entries
* **CRUD Operations:** Create, read, update, and delete travel entries.
* **Rich Content:** Include a title, a detailed description, and multiple photos per entry.
* **Voice Notes:** Record audio notes for your entries, play them back, and see an automatic transcription (requires service integration).

### 📍 Multi-Point Geolocation
* **Automatic Device Location:** Captures your current location via GPS when creating a new entry.
* **Photo Geotagging (EXIF):** Intelligently extracts GPS data from your photos' metadata to add photo-specific locations to your entry.
* **Location List:** Displays a clear, combined list of all locations associated with an adventure.

### 🤖 AI-Powered Tagging
* **Smart Tag Generation:** Select any photo (newly added or previously saved) to generate relevant tags (e.g., "mountain", "beach", "cityscape") using the **Google Vision API**.
* **Manual Tags:** Add and remove your own custom tags for precise organization.

### 📶 Robust Offline-First Sync
* **Instant Local Storage:** All data—entries, photos, and voice notes—is saved instantly to a local **Hive** database, making the app fast and fully functional offline.
* **Automatic Background Sync:** Changes are automatically and reliably synced with the **Supabase** backend whenever an internet connection becomes available.

### 🔍 Smart Search & Filtering
* **Full-Text Search:** A powerful search bar to find entries by keywords in titles, descriptions, locations, or tags.
* **Date Range Filter:** Easily filter your adventures to see entries from a specific period.
* **Proximity Filter:** Find entries that happened within a certain distance of your current location.

### 🎨 Dynamic UI/UX
* **Modern Design:** A clean, organized, and intuitive interface that puts your content first.
* **Light & Dark Mode:** Full support for both light and dark themes.
* **Animated Background:** A subtle, animated video background that changes with the selected theme for an immersive experience.

---
## 🛠 Tech Stack

| Layer | Technology / Package |
| :--- | :--- |
| **Framework** | Flutter (3.x+) |
| **State Management** | Flutter (setState / ValueNotifier) |
| **Local Storage** | [Hive](https://pub.dev/packages/hive) |
| **Backend (BaaS)** | [Supabase](https://supabase.com/) (Auth, PostgreSQL, Storage) |
| **AI Services** | [Google Cloud Vision API](https://cloud.google.com/vision) |
| **API Calls** | [http](https://pub.dev/packages/http) |
| **Routing** | [go_router](https://pub.dev/packages/go_router) |
| **Location** | [geolocator](https://pub.dev/packages/geolocator), [geocoding](https://pub.dev/packages/geocoding), [exif](https://pub.dev/packages/exif) |
| **Connectivity** | [internet_connection_checker](https://pub.dev/packages/internet_connection_checker) |
| **Media** | [image_picker](https://pub.dev/packages/image_picker), [video_player](https://pub.dev/packages/video_player) |

---

## 🚀 Setup Instructions

1️⃣ **Clone the Repository**
```bash
git clone [Your Repository URL]
cd [your-repo-name]