# CAI-6

## Informe de Seguridad Estática - Slither

![Solidity](https://img.shields.io/badge/Solidity-0.8.19-1f2937?logo=solidity)
![Analisis](https://img.shields.io/badge/Slither-101%20detectores-0f766e)
![Hallazgos](https://img.shields.io/badge/Resultados-23-9a3412)
![Estado](https://img.shields.io/badge/Estado-Riesgo%20Residual%20Controlado-166534)

> Contrato auditado: `SubastaVickreySalud.sol`  
> Objetivo: validar seguridad y robustez antes del despliegue en testnet (Ethereum).

---

## 1. Metodologia

Se utilizo **Slither** para auditar de forma estatica el contrato inteligente.

- Detectores ejecutados: **101**
- Resultados reportados: **23**
- Revalidacion manual: **si**, para diferenciar riesgos reales de avisos informativos o mitigados por diseno.

Nota: Slither puede finalizar con codigo de salida `1` cuando detecta hallazgos, incluso si no hay errores de ejecucion.

---

## 2. Resumen Ejecutivo

El analisis identifica patrones conocidos (reentrancia potencial, llamadas de bajo nivel, uso de timestamp y optimizaciones de gas), pero la evaluacion manual confirma que:

- No se observan vulnerabilidades criticas explotables que comprometan fondos.
- Los avisos de reentrancia quedan mitigados por el patron **Checks-Effects-Interactions (CEI)**.
- El riesgo de llamadas en bucle esta acotado por una regla de negocio de maximo **30 participantes**.
- El resto de hallazgos son de optimizacion, estilo o buenas practicas no bloqueantes.

---

## 3. Matriz de Hallazgos

| Categoria | Detectores Slither | Ubicacion principal | Evaluacion final |
|---|---|---|---|
| Reentrancia y llamadas externas | `reentrancy-eth`, `reentrancy-events`, `low-level-calls`, `calls-loop` | `finalizarSubasta()`, `confirmarEntregaYPagar()` | **Mitigado por diseno** |
| Dependencia temporal | `timestamp` | `realizarPuja()`, `iniciarRevelacion()`, `revelarPuja()` | **Riesgo aceptado** |
| Coste de gas en limpieza | `costly-loop` | `inicializarSubasta()` | **Optimizacion no critica** |
| Version del compilador | `solc-version` | Configuracion de compilacion (`^0.8.19`) | **Riesgo aceptado con seguimiento** |
| Buenas practicas | `naming-convention`, `unindexed-event`, `cache-array-length`, `constable-states`, `immutable-states` | Varias | **Mejora recomendada (no bloqueante)** |

---

## 4. Analisis Detallado y Mitigaciones

### 4.1 Reentrancia y Llamadas de Bajo Nivel

**Que reporta Slither**

- Uso de `.call{value: ...}()` para transferencias.
- Llamadas externas dentro de bucles en `finalizarSubasta()`.

**Evaluacion tecnica**

- Se usa `.call()` deliberadamente en lugar de `.transfer()` para evitar limitaciones de gas rigidas.
- Se aplica el patron **CEI**: antes de transferir, se pone el deposito del participante a `0`.
- Si un receptor intenta reentrar, su saldo ya fue invalidado para extraccion doble.
- El bucle de devolucion esta acotado a 30 participantes, evitando crecimiento no controlado del coste de ejecucion.

**Decision**: mitigado por arquitectura actual.

### 4.2 Dependencia de `block.timestamp`

**Que reporta Slither**

- Uso de timestamp para deadline de subasta y marca temporal de pujas.

**Evaluacion tecnica**

- La posible desviacion (segundos) no altera de forma material una subasta de horas/dias.
- El desempate por tiempo no introduce una ventaja economica realista en este contexto.

**Decision**: riesgo aceptado por contexto funcional.

### 4.3 Operaciones Costosas en Bucles

**Que reporta Slither**

- `delete pujas[participantes[i]]` dentro de bucle en `inicializarSubasta()`.

**Evaluacion tecnica**

- Es una observacion de gas, no una vulnerabilidad de seguridad.
- La accion la ejecuta solo `owner` para reiniciar rondas.
- Con limite de 30 participantes, el coste es predecible y asumible.

**Decision**: optimizacion opcional, no bloqueo de seguridad.

### 4.4 Version del Compilador (`^0.8.19`)

**Que reporta Slither**

- Advertencia informativa sobre bugs historicos conocidos de inlining en la rama.

**Evaluacion tecnica**

- El contrato no depende de patrones avanzados de inline assembly que eleven este riesgo.

**Decision**: riesgo aceptado, con recomendacion de upgrade planificado.

### 4.5 Hallazgos Informativos de Calidad

**Detectores**

- `naming-convention`
- `unindexed-event`
- `cache-array-length`
- `constable-states`
- `immutable-states`

**Evaluacion tecnica**

- Impactan en legibilidad, trazabilidad o gas.
- No comprometen la seguridad funcional del contrato.

**Decision**: mejoras de hardening recomendadas para una siguiente iteracion.

---

## 5. Recomendaciones de Hardening (No Bloqueantes)

1. Declarar `constantePorcentaje` como `constant`.
2. Declarar `owner` como `immutable`.
3. Indexar direcciones relevantes en eventos para mejorar trazabilidad off-chain.
4. Cachear `participantes.length` en variables locales dentro de bucles.
5. Evaluar upgrade de compilador a una version mas reciente de `0.8.x` con regresion de pruebas.

---

## 6. Conclusion

Tras el analisis estatico con Slither y la revision manual de hallazgos, el contrato **no presenta vulnerabilidades criticas** que pongan en riesgo fondos o la logica de negocio de la subasta Vickrey en su escenario objetivo.

Las advertencias detectadas se concentran en:

- patrones ya mitigados por diseno (CEI + control de flujo), o
- oportunidades de optimizacion y mantenimiento.

**Veredicto:** apto para continuar con despliegue y testing dinamico en Ethereum Testnet.
