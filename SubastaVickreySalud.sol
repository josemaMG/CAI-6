// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SubastaVickreySalud
 * @dev Implementación de subasta de segundo precio para compra de suministros médicos.
 */
contract SubastaVickreySalud {
    
    address public owner;
    
    enum Estado { Inactiva, Abierta, Revelacion, Finalizada }
    Estado public estadoSubasta;

    uint256 public fechaInicio;
    uint256 public fechaFin;
    uint256 public precioMaximo; // Valor por encima del cual no se admiten pujas
    uint256 public totalPujas;
    uint256 public constantePorcentaje = 10; // Fianza obligatoria del 10% 

    struct PujaOculta {
        bytes32 hashPuja;
        uint256 deposito;
        uint256 marcaDeTiempo;
        bool revelada;
    }

    mapping(address => PujaOculta) public pujas;
    address[] public participantes;

    address public ganador;
    uint256 public pujaGanadora;
    uint256 public segundaMejorPuja;

    event SubastaIniciada(uint256 fechaFin, uint256 precioMax);
    event PujaRealizada(address pujador);
    event FaseRevelacionIniciada();
    event SubastaFinalizada(address ganador, uint256 precioAPagar);
    event EntregaConfirmada(address ganador, uint256 pagoTotal);

    modifier soloOwner() {
        require(msg.sender == owner, "Solo el Servicio de Salud puede ejecutar esto");
        _;
    }

    modifier enEstado(Estado _estado) {
        require(estadoSubasta == _estado, "Accion no permitida en el estado actual");
        _;
    }

    constructor() {
        owner = msg.sender;
        estadoSubasta = Estado.Inactiva;
    }

    // 1. Inicialización
    function inicializarSubasta(uint256 _duracionSegundos, uint256 _precioMaximo) external soloOwner {
        require(estadoSubasta == Estado.Inactiva || estadoSubasta == Estado.Finalizada, "Subasta en curso");
        
        // Limpieza de datos
        for(uint i = 0; i < participantes.length; i++) {
            delete pujas[participantes[i]];
        }
        delete participantes;
        
        ganador = address(0);
        pujaGanadora = type(uint256).max;
        segundaMejorPuja = type(uint256).max;
        totalPujas = 0;
        
        fechaInicio = block.timestamp;
        fechaFin = block.timestamp + _duracionSegundos;
        precioMaximo = _precioMaximo;
        estadoSubasta = Estado.Abierta;

        emit SubastaIniciada(fechaFin, precioMaximo);
    }

    // 2. Fase de Puja
    function realizarPuja(bytes32 _hashPuja) external payable enEstado(Estado.Abierta) {
        require(block.timestamp <= fechaFin, "La subasta ha expirado");
        require(pujas[msg.sender].marcaDeTiempo == 0, "No se puede pujar dos veces");
        require(msg.value > 0, "Debe enviar fondos para la fianza");

        pujas[msg.sender] = PujaOculta({
            hashPuja: _hashPuja,
            deposito: msg.value,
            marcaDeTiempo: block.timestamp, 
            revelada: false
        });

        participantes.push(msg.sender);
        totalPujas++;
        emit PujaRealizada(msg.sender);

        // Cierre automático a las 30 pujas
        if (totalPujas >= 30) {
            estadoSubasta = Estado.Revelacion;
            emit FaseRevelacionIniciada();
        }
    }

    // Transición manual tras el deadline
    function iniciarRevelacion() external soloOwner enEstado(Estado.Abierta) {
        require(block.timestamp > fechaFin, "Aun no se alcanza el limite de tiempo");
        estadoSubasta = Estado.Revelacion;
        emit FaseRevelacionIniciada();
    }

    // 3. Fase de Revelación
    function revelarPuja(uint256 _valorReal, string memory _secreto) external enEstado(Estado.Revelacion) {
        PujaOculta storage puja = pujas[msg.sender];
        require(puja.marcaDeTiempo != 0, "No has participado");
        require(!puja.revelada, "Ya revelada");
        require(_valorReal > 0, "La puja debe ser mayor a 0");
        require(_valorReal <= precioMaximo, "Puja supera el precio maximo");
        
        bytes32 hashCalculado = keccak256(abi.encodePacked(_valorReal, _secreto));
        require(hashCalculado == puja.hashPuja, "El hash no coincide");

        // Verificación de fianza del 10%
        require(puja.deposito >= (_valorReal * constantePorcentaje) / 100, "Fianza insuficiente");

        puja.revelada = true;

        // Lógica Vickrey: Gana el más bajo, paga el segundo más bajo
        if (_valorReal < pujaGanadora) {
            segundaMejorPuja = pujaGanadora;
            pujaGanadora = _valorReal;
            ganador = msg.sender;
        } else if (_valorReal == pujaGanadora) {
            // Desempate por orden temporal
            if (puja.marcaDeTiempo < pujas[ganador].marcaDeTiempo) {
                ganador = msg.sender;
            } else {
                segundaMejorPuja = _valorReal;
            }
        } else if (_valorReal < segundaMejorPuja) {
            segundaMejorPuja = _valorReal;
        }
    }

    // 4. Finalizar Subasta y Devoluciones Automáticas
    function finalizarSubasta() external soloOwner enEstado(Estado.Revelacion) {
        estadoSubasta = Estado.Finalizada;
        
        // Caso de puja única
        if (segundaMejorPuja == type(uint256).max && ganador != address(0)) {
            segundaMejorPuja = pujaGanadora;
        }

        // Devolución de depósitos a perdedores
        for(uint i = 0; i < participantes.length; i++) {
            address participante = participantes[i];
            if (participante != ganador) {
                uint256 aDevolver = pujas[participante].deposito;
                pujas[participante].deposito = 0;
                if (aDevolver > 0) {
                    (bool exito, ) = payable(participante).call{value: aDevolver}("");
                    require(exito, "Fallo al devolver fianza");
                }
            }
        }

        emit SubastaFinalizada(ganador, segundaMejorPuja);
    }

    // 5. Confirmación y Pago Final
    function confirmarEntregaYPagar() external soloOwner enEstado(Estado.Finalizada) {
        require(ganador != address(0), "No hay ganador");
        
        uint256 fianzaDevuelta = pujas[ganador].deposito;
        pujas[ganador].deposito = 0; 
        
        uint256 pagoTotal = segundaMejorPuja + fianzaDevuelta;
        
        (bool exito, ) = payable(ganador).call{value: pagoTotal}("");
        require(exito, "Fallo al realizar el pago final");
        
        emit EntregaConfirmada(ganador, pagoTotal);
    }

    receive() external payable {}
}