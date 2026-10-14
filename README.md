# DAO Governance — Solidity & Foundry

A decentralized governance system built with Solidity, Foundry, and OpenZeppelin Contracts.

The project implements ERC-20 token-weighted voting, delegation, historical voting checkpoints, proposal creation, quorum requirements, and delayed execution through a TimelockController.

**Project status:** Deployed on Ethereum Sepolia · 4 contracts verified · 47 passing local tests.

---

## English Version

### Architecture

**GovernanceToken (IGOV)**
- ERC-20 token with an initial supply of 1,000 IGOV.
- Delegated voting power using ERC20Votes.
- Historical checkpoints for snapshot-based voting.
- ERC20Permit support.

**DAOGovernance**
- Proposal creation and token-weighted voting.
- Against, For, and Abstain voting options.
- 10% quorum.
- Direct execution of successful proposals, implemented as a comparison with timelocked governance.

**TimelockedDAOGovernance**
- OpenZeppelin Governor integrated with TimelockController.
- Proposal queuing and delayed execution.
- Governor assigned the proposer, executor, and canceller roles.

**TimelockController**
- Minimum execution delay of 48 hours after queuing.
- Role-based access control.
- Self-administration after the deployer renounces its administrator role.

**TimelockedProtocolSettings**
- Marketplace configuration controlled by TimelockController.
- Initial marketplace fee: 2.5%.
- Maximum marketplace fee: 10%.

### Governance Lifecycle

1. A participant submits a proposal.
2. Voting begins after a one-block delay.
3. Members vote using their voting power recorded at the proposal snapshot.
4. After the 20-block voting period, the Governor evaluates the result and quorum.
5. A successful proposal can be queued through TimelockController.
6. At least 48 hours must pass after queuing.
7. An authorized executor submits an execution transaction.
8. TimelockController executes the operation and updates the governed contract.

**Important:** Smart contracts enforce the waiting period but do not automatically submit transactions. An approved and queued proposal remains unexecuted until an authorized transaction is submitted.

### Sepolia Deployment

**Network:** Ethereum Sepolia  
**Chain ID:** 11155111  
**Deployment date:** October 14, 2026

All four contracts were deployed successfully using `script/DeployDAO.s.sol`. Source-code verification returned `exact_match` on Sourcify.

| Contract | Sepolia address |
|---|---|
| GovernanceToken | `0xf5F0768c8a71F01bE8f9d395b9362C3Ec358242e` |
| TimelockController | `0x6aCD52f9fE699D42fb70F27f4B1863B1d106EE55` |
| TimelockedDAOGovernance | `0x655e7aAccA97F9c75B71063994D67176b2ea37a0` |
| TimelockedProtocolSettings | `0x5e76000B21bA04af057D0862c486D190744121c6` |

**Verified contracts:**
- [GovernanceToken](https://repo.sourcify.dev/11155111/0xf5F0768c8a71F01bE8f9d395b9362C3Ec358242e)
- [TimelockController](https://repo.sourcify.dev/11155111/0x6aCD52f9fE699D42fb70F27f4B1863B1d106EE55)
- [TimelockedDAOGovernance](https://repo.sourcify.dev/11155111/0x655e7aAccA97F9c75B71063994D67176b2ea37a0)
- [TimelockedProtocolSettings](https://repo.sourcify.dev/11155111/0x5e76000B21bA04af057D0862c486D190744121c6)

**Initial governance token distribution:**
- Deployer: 500 IGOV, self-delegated.
- Member B: 300 IGOV.
- Member C: 200 IGOV.

Members B and C must delegate their tokens to activate their voting power.

### Technology Stack

Solidity · Foundry · OpenZeppelin Contracts 5.x · ERC20Votes · Governor · TimelockController · Ethereum Sepolia

### Testing

47 local tests covering:
- Token delegation and historical checkpoints.
- Proposal creation, voting, and quorum.
- Double-voting prevention.
- Successful proposal execution.
- Timelock delays and role-based permissions.
- Calldata manipulation scenarios.
- Governance security and attack scenarios.

Run:

```bash
forge build --sizes
forge test -vv
forge fmt --check
```

### Security Considerations

This project is educational and has not undergone an independent security audit.

Token-weighted governance can be captured by concentrated voting power. A timelock provides a delay before execution but does not guarantee that approved proposals are safe.

There is no independent emergency council or special supermajority requirement for critical proposals.

The one-block voting delay and 20-block voting period are demonstration settings and are not appropriate for production protocols handling high-value assets.

Source-code verification confirms that the published source corresponds to the deployed bytecode; it does not establish that the contracts are vulnerability-free.

Do not use these contracts to manage real funds without additional security review, governance safeguards, and independent auditing.

---

## Versión en Español

### Descripción

Sistema de gobernanza descentralizada desarrollado con Solidity, Foundry y OpenZeppelin Contracts.

Permite crear propuestas, delegar poder de voto, votar mediante tokens ERC-20, establecer quórums y ejecutar decisiones aprobadas utilizando un TimelockController.

**Estado:** Desplegado en Ethereum Sepolia · 4 contratos verificados · 47 pruebas locales superadas.

### Arquitectura

**GovernanceToken (IGOV)**
- Token ERC-20 con suministro inicial de 1.000 IGOV.
- Delegación de poder de voto mediante ERC20Votes.
- Checkpoints históricos para calcular votos en un bloque determinado.
- Soporte de ERC20Permit.

**DAOGovernance**
- Creación de propuestas y votación ponderada por tokens.
- Opciones Against, For y Abstain.
- Quórum del 10%.
- Ejecución directa de propuestas aprobadas para comparar arquitecturas de gobernanza.

**TimelockedDAOGovernance**
- Governor conectado a TimelockController.
- Programación y ejecución diferida de propuestas.
- Roles de proposer, executor y canceller asignados al Governor.

**TimelockController**
- Retraso mínimo de 48 horas desde la programación de una operación.
- Control de acceso basado en roles.
- Administración autónoma tras la renuncia del desplegador a su rol administrativo.

**TimelockedProtocolSettings**
- Configuración del marketplace controlada por TimelockController.
- Comisión inicial del 2,5%.
- Comisión máxima permitida del 10%.

### Flujo de Gobernanza

1. Un participante presenta una propuesta.
2. La votación comienza tras un bloque de espera.
3. Los miembros votan utilizando su poder de voto histórico.
4. Finalizado el periodo de 20 bloques, el Governor evalúa la votación y el quórum.
5. Una propuesta aprobada puede programarse en TimelockController.
6. Deben transcurrir al menos 48 horas desde su programación.
7. Un ejecutor autorizado envía la transacción correspondiente.
8. TimelockController ejecuta la operación y actualiza el contrato gobernado.

**Importante:** El timelock impide ejecutar operaciones antes de tiempo, pero no ejecuta automáticamente las propuestas cuando finaliza el plazo.

### Despliegue en Sepolia

**Red:** Ethereum Sepolia  
**Chain ID:** 11155111  
**Fecha:** 14 de octubre de 2026

Se desplegaron correctamente los cuatro contratos mediante `script/DeployDAO.s.sol`.

El código fuente de los cuatro contratos se verificó en Sourcify con resultado `exact_match`.

| Contrato | Dirección |
|---|---|
| GovernanceToken | `0xf5F0768c8a71F01bE8f9d395b9362C3Ec358242e` |
| TimelockController | `0x6aCD52f9fE699D42fb70F27f4B1863B1d106EE55` |
| TimelockedDAOGovernance | `0x655e7aAccA97F9c75B71063994D67176b2ea37a0` |
| TimelockedProtocolSettings | `0x5e76000B21bA04af057D0862c486D190744121c6` |

Las direcciones pueden consultarse en los enlaces de Sourcify incluidos en la versión inglesa.

**Distribución inicial:**
- Desplegador: 500 IGOV, autodelegados.
- Miembro B: 300 IGOV.
- Miembro C: 200 IGOV.

Los miembros B y C deben delegar sus tokens para activar su poder de voto.

### Tecnologías

Solidity · Foundry · OpenZeppelin Contracts 5.x · ERC20Votes · Governor · TimelockController · Ethereum Sepolia

### Pruebas

47 pruebas locales que cubren:
- Delegación y checkpoints históricos.
- Propuestas, votaciones y quórum.
- Prevención del doble voto.
- Ejecución de propuestas.
- Permisos y retrasos del timelock.
- Manipulación de calldata.
- Escenarios de seguridad y captura de gobernanza.

Ejecutar:

```bash
forge build --sizes
forge test -vv
forge fmt --check
```

### Seguridad y Limitaciones

Proyecto educativo sin auditoría independiente.

La concentración de tokens puede permitir la captura de la gobernanza. El timelock retrasa las operaciones, pero no garantiza que las decisiones aprobadas sean seguras.

No existe un consejo de emergencia independiente ni un requisito especial de supermayoría para propuestas críticas.

Los periodos de espera de un bloque y votación de 20 bloques son demostrativos y no resultan adecuados para protocolos de producción que gestionen activos de alto valor.

La verificación del código fuente no equivale a una auditoría de seguridad.

No debe utilizarse para gestionar fondos reales sin revisar el diseño de gobernanza, añadir protecciones y realizar auditorías independientes.
