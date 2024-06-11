import Metal

enum PipelineIndex: Int {
    case waveVertexUpdate
    case gridIndexUpdate
}

class MetalContext {
    enum Error : Swift.Error {
        case libraryNotFound
        case functionNotFound(name: String)
    }

    static let shared = {
        do {
            return try MetalContext()
        } catch {
            fatalError("Error occurred while initializing shared Metal context: \(error)")
        }
    }()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var computePipelines: [MTLComputePipelineState] = []

    init(device: MTLDevice? = nil, commandQueue: MTLCommandQueue? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            fatalError()
        }
        guard let commandQueue = commandQueue ?? device.makeCommandQueue() else {
            fatalError()
        }
        self.device = device
        self.commandQueue = commandQueue

        try makePipelines()
    }

    func makePipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw Error.libraryNotFound
        }

        let vertexFunctionName = "update_wave_vertex"
        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            throw Error.functionNotFound(name: vertexFunctionName)
        }
        let vertexPipeline = try device.makeComputePipelineState(function: vertexFunction)
        computePipelines.insert(vertexPipeline, at: PipelineIndex.waveVertexUpdate.rawValue)

        let indexFunctionName = "update_grid_indices"
        guard let indexFunction = library.makeFunction(name: indexFunctionName) else {
            throw Error.functionNotFound(name: indexFunctionName)
        }
        let indexPipeline = try device.makeComputePipelineState(function: indexFunction)
        computePipelines.insert(indexPipeline, at: PipelineIndex.gridIndexUpdate.rawValue)
    }
}
