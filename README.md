# WiFA — Native macOS Wi-Fi Analyzer

## Сборка и запуск

1. **Соберите приложение:**
   ```bash
   ./build.sh
   ```
   Результат: `build/WiFA-Universal/WiFA.app`

2. **Запуск:**
    - Откройте полученный `.app` файл.

3. **Разрешения:**
    - Для отображения BSSID/SSID сети дайте приложению доступ к Location Services.
    - При первом запуске macOS автоматически попросит доступ.
    - Если нет — вручную: System Settings → Privacy & Security → Location Services → Разрешите для "WiFA".

4. **Требований к системе:** macOS 13+ (Apple Silicon или Intel).
