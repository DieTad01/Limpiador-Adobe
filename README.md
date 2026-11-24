# Limpiador Adobe (macOS)

Es una app de barra de menú: aparece un icono de disco junto al reloj, con los GB libres.
Borra la caché de Adobe cada 30 minutos o cuando eliges **🧹 Limpiar caché de Adobe ahora**.

## Qué hace y qué NO hace

- **Nunca cierra programas.** Solo revisa qué apps están abiertas.
- **Si una app de Adobe está abierta** (Photoshop, Illustrator, Premiere, After Effects, etc.):
  - la limpieza automática **no borra nada**;
  - la limpieza manual solo borra registros (logs).
- **Con todas las apps de Adobe cerradas** borra:
  - `~/Library/Caches/Adobe` y las cachés de Photoshop, Illustrator, Premiere y After Effects;
  - Media Cache, Media Cache Files y Peak Files de video;
  - archivos temporales de Photoshop y After Effects.
- **No toca** proyectos, preferencias, plugins, la sesión de Creative Cloud ni "Team Projects Cache".

## Compilar (no se puede en Windows)

1. El código vive en [DieTad01/Limpiador-Adobe](https://github.com/DieTad01/Limpiador-Adobe). Cada push a `main` compila solo con GitHub Actions.
2. También puedes compilar a mano: **Actions → Compilar Limpiador Adobe Universal → Run workflow**.
3. Cuando termine, abre la ejecución y descarga **LimpiadorAdobe-Mac** (abajo, en *Artifacts*).
   Ese zip trae `LimpiadorAdobe-Universal.zip` adentro, y ese es el que se reparte.

El binario es universal: funciona en Mac con Intel y con Apple Silicon, desde macOS 11 (Big Sur).

## Instalar en cada Mac

1. Descomprime `LimpiadorAdobe-Universal.zip` y arrastra **Limpiador.app** a **Aplicaciones**.
2. Ábrela con doble clic. macOS la va a bloquear porque no está firmada por un desarrollador de Apple.
3. Ve a **Ajustes del Sistema → Privacidad y seguridad**, baja hasta el aviso de "Limpiador" y pulsa **Abrir de todos modos**. Escribe tu contraseña.
4. Aparece el icono de disco en la barra de menú (arriba a la derecha). No sale en el Dock.

Solo se pide la primera vez.

**Para que arranque al prender la Mac:** Ajustes del Sistema → General → Ítems de inicio → **+** → elige Limpiador.

## Quitarla

Menú del icono → **Salir**, y borra Limpiador.app de Aplicaciones.
