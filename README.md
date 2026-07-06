# 🚀 SistemDaily: El Sistema Inteligente de Vida (Life OS)

SistemDaily es una aplicación móvil desarrollada en **Flutter** diseñada con una estética de **Minimalist Glassmorphism**. Funciona como un "segundo cerebro" personal y un asistente de vida diario que integra el seguimiento de hábitos, notas interconectadas y alarmas inteligentes.

Todo el procesamiento de Inteligencia Artificial (análisis de texto y validación de imágenes) se ejecuta de forma **privada y local** en tu propio servidor remoto a través de **Ollama**.

---

## 🛠️ Arquitectura del Sistema

```mermaid
graph TD
    A[SistemDaily App - Flutter] -->|Autenticación y Datos| B[Supabase]
    A -->|Procesamiento de Notas, Voz e Imágenes| C[Servidor IA Local - Ollama API]
    
    subgraph Supabase Database
        B --> D[(PostgreSQL)]
        D --> D1[Tabla de Usuarios / Perfiles]
        D --> D2[Tabla de Hábitos e Historial]
        D --> D3[Tabla de Notas con Vectores pgvector]
        D --> D4[Configuración de Alarmas]
    end

    subgraph Servidor IA Local (Ollama)
        C --> E[qwen3-vl:8b - Modelo de Visión para Alarmas]
        C --> F[qwen2.5-coder:14b - Razonamiento de Notas y Conexiones]
        C --> G[bge-m3 - Búsqueda Semántica de Notas]
    end

    subgraph Almacenamiento
        B --> H[(Supabase Storage)]
        H -->|Fotos de Alarmas / Adjuntos| D
    end
```

---

## 🖥️ Configuración del Servidor de IA (Ollama)

El servidor remoto ha sido diagnosticado y configurado con los siguientes detalles:

*   **Dirección Host**: `63.141.255.7`
*   **Puerto de Ollama**: `11434` (Escuchando públicamente en `0.0.0.0:11434`)
*   **Hardware del Servidor**:
    *   **CPU**: Intel Xeon E5-2697 v3 (x86_64) @ 2.60GHz
    *   **Memoria RAM**: 125 GiB RAM
    *   **GPU**: NVIDIA Tesla V100 PCIe (16 GB VRAM) con soporte CUDA 13.0
*   **Servicio Systemd**:
    *   Fichero de configuración de overrides: `/etc/systemd/system/ollama.service.d/override.conf` conteniendo `Environment="OLLAMA_HOST=0.0.0.0"`.
    *   Ruta de almacenamiento de modelos: `/home/ollama-models` (según `models.conf`).

### Modelos de IA Instalados en el Servidor
1.  **`qwen2.5-coder:14b`** (Texto/Razonamiento): Utilizado como copiloto en el chat interactivo, organizador de tareas y recomendador semántico de conexiones entre notas.
2.  **`qwen3-vl:8b`** (Visión/Multimodal): Utilizado para la validación visual de la alarma anti-procrastinación.
3.  **`bge-m3:latest`** (Embeddings): Para la indexación semántica y búsqueda vectorial en el Segundo Cerebro.

---

## 🎨 Guía de Diseño Visual: Glassmorphism

La interfaz móvil implementa una estética de cristal translúcido (cristal esmerilado):
*   **Degradados de Fondo**: Un fondo oscuro profundo (`0xFF0F0C20` a `0xFF06040A`) con dos orbes de luz difusos e indirectos (púrpura y azul) generados en base al tamaño de pantalla mediante `BackdropFilter` con difuminados de alta densidad (blur de 100 y 120).
*   **Tarjetas de Cristal**: Contenedores translúcidos (`GlassContainer`) creados con filtros de desenfoque (`ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0)`) con bordes finos blancos semi-transparentes de 1.2px y opacidades bajas de fondo de entre 5% y 15%.
*   **Navegación**: Un menú inferior flotante y curvo que cambia dinámicamente de color de selección en base a la pestaña seleccionada (Púrpura, Azul, Cyan, Coral).

---

## 📁 Estructura del Proyecto Flutter

```text
lib/
├── main.dart                       # Inicialización de la app, Providers y redirección dinámica
├── core/
│   ├── theme/
│   │   └── glass_theme.dart        # Paleta, configuraciones del tema y widgets reutilizables (GlassContainer, DeepBackground)
│   ├── network/
│   │   └── local_ai_client.dart    # Cliente HTTP para Ollama con compatibilidad OpenAI (Qwen & Qwen-VL)
│   └── providers/
│       └── settings_provider.dart  # Notifier de Riverpod para persistencia de la URL del servidor e IP de Supabase
└── features/
    ├── setup/
    │   └── setup_screen.dart       # Formulario inicial de login y tests de conexión con servidor local de IA
    ├── dashboard/
    │   └── dashboard_screen.dart   # Contenedor principal de pestañas con barra flotante Glassmorphic
    ├── habits/
    │   └── habits_tab.dart         # Grid de hábitos e integración con Qwen para feedbacks
    ├── alarm/
    │   └── alarm_tab.dart          # Configuración de alarma, selección de target y testeo con cámara (Qwen-VL)
    ├── notes/
    │   └── notes_tab.dart          # Segundo cerebro: Markdown editor y visualizador de grafo interactivo en 2D (CustomPainter)
    └── chat/
        └── chat_tab.dart           # Copiloto conversacional con inyección automática de contexto (hábitos y notas)
```

---

## 🚀 Instrucciones de Ejecución

1.  Asegúrate de contar con el SDK de Flutter y un emulador de Android/iOS o dispositivo físico conectado.
2.  Para iniciar la aplicación, ejecuta desde la terminal del proyecto:
    ```bash
    /home/jhon/Documentos/TerminalAgent/sdk/flutter/bin/flutter run
    ```
3.  Al abrir la app por primera vez, verás la pantalla de configuración. Completa los campos con las siguientes credenciales:
    *   **Supabase URL** y **Anon Key** de tu proyecto Supabase.
    *   **URL de API Local**: `http://63.141.255.7:11434`
    *   **Modelo de Texto (Qwen)**: `qwen2.5-coder:14b`
    *   **Modelo de Visión (Qwen-VL)**: `qwen3-vl:8b`
4.  Presiona el botón de **Test de Conexión** (icono de rayo) para validar que la conexión al servidor remoto sea exitosa antes de guardar y acceder al dashboard.
