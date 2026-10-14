# Luz de día

- El usuario vio el mediodía "súper iluminado y sin sombras" y pensó en dos iluminaciones encimadas (ya pasó una vez con la luz que traía el lugar). No lo era: el perfil de pleno día de `client/DayCycle` (`KEYS`, horas 9, 12 y 16) llevaba la luz de relleno muy alta y, con el sol casi en vertical, se comía las sombras. Ahora `ambient` va sobre 95 y `outdoor` sobre 120, con brillo de 2,2 a 2,4: no subirlos sin mirarlo a mediodía.
- Para ver una hora concreta (solo Studio): `workspace:SetAttribute("ClockForce", 12)` desde `Client` deja el reloj fijo; `nil` lo suelta. Para descartar luces duplicadas, contar los hijos de `Lighting` (un `Atmosphere`, un `Bloom`, un `ColorCorrection`, un `SunRays`, un `Sky`, un `DepthOfField`) y mirar `ExposureCompensation` (0).
