let mapData = null;
let canvas, ctx;
let cellSize = 40;
let zoom = 1;
let offsetX = 0;
let offsetY = 0;
let currentTool = 'draw';
let selectedTile = 0;
let selectedEntity = null;
let entities = [];
let tooltip;
let canvasWrapper;
let isPanning = false;
let panStart = { x: 0, y: 0 };
let history = [];
let historyIndex = -1;
let copyStart = null;
let copyEnd = null;
let copiedData = null;
let isDragging = false;
let draggedEntity = null;
let draggedTile = null;
let currentMapName = 'shader_maze_1.json';
let currentMapPath = '../assets/data/shader_maze_1.json';
const SMAP_MAGIC = 'SMAPBIN1';
const DEFAULT_SMAP_CHUNK_SIZE = 32;

const entityDefaults = {
    player_spawn: { angle: 18, pitch: 0, fov: 84, height: 1.28, bobAmount: 0.05, bobSpeed: 15.0 },
    table: {
        width: 1.8,
        depth: 1.1,
        topHeight: 0.80,
        thickness: 0.08,
        legThickness: 0.10,
        desc: '木桌',
        detail: '一张摆放在迷宫深处的木桌。桌板和桌腿都由着色器按解析几何体实时求交，不依赖顶点网格。'
    },
    pyramid: {
        size: 0.70,
        height: 0.68,
        desc: '金字塔',
        detail: '这座小型金字塔并不是传统模型，而是由四个三角面在着色器里逐像素求交得到的结果。'
    },
    point_light: {
        color: '#ffd7a0',
        intensity: 1.0,
        radius: 4.0,
        height: 1.65,
        pulseAmount: 0.0,
        pulseSpeed: 0.0,
        phase: 0.0
    },
    statue_sprite: { desc: '雕像', detail: '' }
};

function escapeHtml(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
}

function getTileLayer() {
    return mapData.layers.find(l => l.type === 'tilelayer');
}

function getEntityLayer() {
    return mapData.layers.find(l => l.type === 'objectlayer');
}

function getSmapName() {
    if (currentMapName.toLowerCase().endsWith('.json')) {
        return currentMapName.slice(0, -5) + '.smap';
    }

    return currentMapName + '.smap';
}

function downloadBlob(blob, fileName) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function compressChunk(buffer) {
    if (typeof CompressionStream !== 'undefined') {
        const stream = new Blob([buffer]).stream().pipeThrough(new CompressionStream('deflate'));
        const compressedBuffer = await new Response(stream).arrayBuffer();
        return new Uint8Array(compressedBuffer);
    }

    throw new Error('当前浏览器不支持 CompressionStream，无法导出 .smap');
}

async function buildSmapBlob() {
    syncEntityLayer();

    const metadata = mapData.metadata || {};
    const tileLayer = getTileLayer();
    const objectLayer = getEntityLayer();
    const width = Number(metadata.width || 0);
    const height = Number(metadata.height || 0);
    const chunkSize = Number(metadata.smapChunkSize || DEFAULT_SMAP_CHUNK_SIZE);
    const chunkColumns = Math.ceil(width / chunkSize);
    const chunkRows = Math.ceil(height / chunkSize);
    const chunkBuffers = [];
    const chunks = [];
    let offset = 0;

    for (let cy = 0; cy < chunkRows; cy++) {
        for (let cx = 0; cx < chunkColumns; cx++) {
            const chunkWidth = Math.min(chunkSize, width - cx * chunkSize);
            const chunkHeight = Math.min(chunkSize, height - cy * chunkSize);
            const rawTiles = new Uint8Array(chunkWidth * chunkHeight * 2);
            let writeOffset = 0;

            for (let y = 0; y < chunkHeight; y++) {
                for (let x = 0; x < chunkWidth; x++) {
                    const mapX = cx * chunkSize + x;
                    const mapY = cy * chunkSize + y;
                    const tileId = Number(tileLayer.data[mapY * width + mapX] || 0);
                    rawTiles[writeOffset] = tileId & 0xff;
                    rawTiles[writeOffset + 1] = (tileId >> 8) & 0xff;
                    writeOffset += 2;
                }
            }

            const compressed = await compressChunk(rawTiles.buffer);
            chunkBuffers.push(compressed);
            chunks.push({
                cx,
                cy,
                width: chunkWidth,
                height: chunkHeight,
                offset,
                size: compressed.byteLength
            });
            offset += compressed.byteLength;
        }
    }

    const header = {
        version: 1,
        metadata,
        chunkSize,
        chunkColumns,
        chunkRows,
        tilesets: mapData.tilesets || [],
        objects: objectLayer?.objects || [],
        chunks
    };

    const encoder = new TextEncoder();
    const magicBytes = encoder.encode(SMAP_MAGIC);
    const headerBytes = encoder.encode(JSON.stringify(header));
    const headerLength = new Uint8Array(4);
    const headerView = new DataView(headerLength.buffer);
    headerView.setUint32(0, headerBytes.byteLength, true);

    return new Blob(
        [magicBytes, headerLength, headerBytes, ...chunkBuffers],
        { type: 'application/octet-stream' }
    );
}

function getTileColor(tileId) {
    if (tileId === 0) {
        return '#1a1a1a';
    }

    const tileset = mapData.tilesets.find(t => Number(t.id) === Number(tileId));
    return tileset?.color || '#666666';
}

function getTileSizeMeters() {
    return Number(mapData?.metadata?.tileSize || 1);
}

function metersToCells(meters) {
    return Number(meters || 0) / Math.max(getTileSizeMeters(), 0.0001);
}

function syncEntityLayer() {
    const entityLayer = getEntityLayer();
    if (entityLayer) {
        entityLayer.objects = entities;
    }
}

function updateCurrentMapLabel() {
    const label = document.getElementById('current-map');
    if (label) {
        label.textContent = `当前地图: ${currentMapName}`;
    }
}

function updateEntityTypeOptions() {
    const select = document.getElementById('entity-type');
    const previousValue = select.value;
    const typeSet = new Set(['player_spawn', 'table', 'pyramid', 'point_light', 'statue_sprite']);

    entities.forEach(entity => typeSet.add(entity.type));

    select.innerHTML = '';
    Array.from(typeSet).sort().forEach(type => {
        const option = document.createElement('option');
        option.value = type;
        option.textContent = type;
        select.appendChild(option);
    });

    if (Array.from(typeSet).includes(previousValue)) {
        select.value = previousValue;
    }
}

function getEntityBounds(entity) {
    const props = entity.properties || {};

    if (entity.type === 'table') {
        const width = metersToCells(props.width || entityDefaults.table.width);
        const depth = metersToCells(props.depth || entityDefaults.table.depth);
        return {
            minX: entity.x - width * 0.5,
            maxX: entity.x + width * 0.5,
            minY: entity.y - depth * 0.5,
            maxY: entity.y + depth * 0.5
        };
    }

    if (entity.type === 'pyramid') {
        const size = metersToCells(props.size || entityDefaults.pyramid.size);
        return {
            minX: entity.x - size * 0.5,
            maxX: entity.x + size * 0.5,
            minY: entity.y - size * 0.5,
            maxY: entity.y + size * 0.5
        };
    }

    if (entity.type === 'point_light') {
        const radius = metersToCells(props.radius || entityDefaults.point_light.radius);
        return {
            minX: entity.x - radius,
            maxX: entity.x + radius,
            minY: entity.y - radius,
            maxY: entity.y + radius
        };
    }

    return {
        minX: entity.x - 0.35,
        maxX: entity.x + 0.35,
        minY: entity.y - 0.35,
        maxY: entity.y + 0.35
    };
}

function findEntityAt(x, y) {
    for (let i = entities.length - 1; i >= 0; i--) {
        const entity = entities[i];
        const bounds = getEntityBounds(entity);
        if (x >= bounds.minX && x <= bounds.maxX && y >= bounds.minY && y <= bounds.maxY) {
            return entity;
        }
    }

    return null;
}

async function init() {
    canvas = document.getElementById('canvas');
    ctx = canvas.getContext('2d');
    tooltip = document.getElementById('tooltip');
    canvasWrapper = document.getElementById('canvas-wrapper');

    canvas.width = canvasWrapper.clientWidth;
    canvas.height = canvasWrapper.clientHeight;

    await loadMap();
    setupUI();

    canvasWrapper.addEventListener('wheel', handleWheel, { passive: false });
    window.addEventListener('resize', () => {
        canvas.width = canvasWrapper.clientWidth;
        canvas.height = canvasWrapper.clientHeight;
        render();
    });

    centerMap();
    render();
}

function centerMap() {
    offsetX = (canvas.width - mapData.metadata.width * cellSize * zoom) / 2;
    offsetY = (canvas.height - mapData.metadata.height * cellSize * zoom) / 2;
}

async function loadMap() {
    try {
        const response = await fetch(currentMapPath);
        mapData = await response.json();
    } catch (e) {
        const embedded = window.EMBEDDED_MAPS?.[currentMapName];
        if (embedded) {
            mapData = JSON.parse(JSON.stringify(embedded));
        } else {
            mapData = {
                metadata: { name: 'FallbackMap', version: '1.0', width: 24, height: 18, tileSize: 0.5, unit: 'meter' },
                layers: [
                    { name: 'maze', type: 'tilelayer', data: new Array(24 * 18).fill(0) },
                    { name: 'entities', type: 'objectlayer', objects: [] }
                ],
                tilesets: []
            };
        }
    }

    entities = getEntityLayer().objects;
    updateCurrentMapLabel();
    resetHistory();
}

function handleWheel(e) {
    e.preventDefault();

    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;

    const worldX = (mouseX - offsetX) / zoom;
    const worldY = (mouseY - offsetY) / zoom;

    const delta = e.deltaY > 0 ? 0.9 : 1.1;
    const newZoom = Math.max(0.1, Math.min(5, zoom * delta));

    offsetX = mouseX - worldX * newZoom;
    offsetY = mouseY - worldY * newZoom;
    zoom = newZoom;

    document.getElementById('zoom-info').textContent = `缩放: ${Math.round(zoom * 100)}%`;
    render();
}

function setupUI() {
    updateTilePalette();
    updateEntityTypeOptions();

    // Tools
    document.getElementById('tool-pan').onclick = () => currentTool = 'pan';
    document.getElementById('tool-draw').onclick = () => currentTool = 'draw';
    document.getElementById('tool-erase').onclick = () => { currentTool = 'draw'; selectedTile = 0; };
    document.getElementById('tool-entity').onclick = () => currentTool = 'entity';
    document.getElementById('tool-select').onclick = () => currentTool = 'select';
    document.getElementById('tool-copy').onclick = () => { currentTool = 'copy'; copyStart = null; copyEnd = null; };

    document.getElementById('undo').onclick = undo;
    document.getElementById('redo').onclick = redo;

    // Canvas events
    canvas.onmousedown = handleCanvasClick;
    canvas.onmousemove = handleCanvasMove;
    canvas.onmouseup = handleCanvasUp;
    canvas.onmouseleave = () => { isPanning = false; isDragging = false; };

    // Map resize
    document.getElementById('map-width').value = mapData.metadata.width;
    document.getElementById('map-height').value = mapData.metadata.height;
    document.getElementById('resize-map').onclick = resizeMap;

    // Save/Load
    document.getElementById('save').onclick = () => {
        void saveMap();
    };
    document.getElementById('import').onchange = importMap;
    document.getElementById('reload-map').onclick = async () => {
        currentMapPath = document.getElementById('map-source').value;
        currentMapName = currentMapPath.split('/').pop();
        await loadMap();
        updateTilePalette();
        updateEntityTypeOptions();
        updateEntityList();
        showProperties();
        centerMap();
        render();
    };
    document.getElementById('center-map').onclick = () => {
        centerMap();
        render();
    };

    updateEntityList();
}

function updateTilePalette() {
    const palette = document.getElementById('tile-palette');
    palette.innerHTML = '';

    const emptyBtn = document.createElement('div');
    emptyBtn.className = 'tile-btn active';
    emptyBtn.dataset.tileId = '0';
    emptyBtn.style.background = '#1a1a1a';
    emptyBtn.textContent = '0';
    emptyBtn.title = 'Empty - 空地';
    emptyBtn.onclick = () => {
        document.querySelectorAll('.tile-btn').forEach(b => b.classList.remove('active'));
        emptyBtn.classList.add('active');
        selectedTile = 0;
    };
    palette.appendChild(emptyBtn);

    mapData.tilesets
        .filter(tileset => Number(tileset.id) !== 0)
        .sort((a, b) => Number(a.id) - Number(b.id))
        .forEach(tileset => {
        const btn = document.createElement('div');
        btn.className = 'tile-btn';
        btn.dataset.tileId = String(tileset.id);
        btn.style.background = tileset.color;
        btn.textContent = tileset.id;
        const kind = tileset.properties?.kind || 'unknown';
        const height = tileset.height ? ` (高度: ${tileset.height}m)` : '';
        const passable = tileset.passable === false ? ' [不可通行]' : '';
        btn.title = `${tileset.name}\n类型: ${kind}${height}${passable}`;
        btn.onclick = () => {
            document.querySelectorAll('.tile-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            selectedTile = tileset.id;
        };
        palette.appendChild(btn);
    });
}

function handleCanvasClick(e) {
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    const x = Math.floor((mouseX - offsetX) / (cellSize * zoom));
    const y = Math.floor((mouseY - offsetY) / (cellSize * zoom));
    const worldX = (mouseX - offsetX) / (cellSize * zoom);
    const worldY = (mouseY - offsetY) / (cellSize * zoom);

    if (currentTool === 'pan') {
        isPanning = true;
        panStart = { x: mouseX - offsetX, y: mouseY - offsetY };
        canvas.style.cursor = 'grabbing';
        return;
    }

    if (currentTool === 'copy') {
        isDragging = true;
        copyStart = { x, y };
        copyEnd = null;
        return;
    }

    if (currentTool === 'paste') {
        pasteRegion(x, y);
        currentTool = 'draw';
        render();
        return;
    }

    if (currentTool === 'select') {
        draggedEntity = findEntityAt(worldX, worldY);
        if (draggedEntity) {
            saveHistory();
            isDragging = true;
            selectedEntity = draggedEntity;
            updateEntityList();
            showProperties();
            return;
        }
    }

    if (currentTool === 'draw') {
        const layer = getTileLayer();
        const idx = y * mapData.metadata.width + x;
        if (idx >= 0 && idx < layer.data.length && layer.data[idx] !== 0) {
            saveHistory();
            draggedTile = { x, y, originalTile: layer.data[idx] };
            isDragging = true;
            return;
        }
        saveHistory();
        setTile(x, y, selectedTile);
        render();
    } else if (currentTool === 'entity') {
        saveHistory();
        addEntity(x + 0.5, y + 0.5);
        render();
    }
}

function handleCanvasMove(e) {
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;

    if (isPanning) {
        offsetX = mouseX - panStart.x;
        offsetY = mouseY - panStart.y;
        render();
        return;
    }

    if (isDragging && currentTool === 'copy') {
        const x = Math.floor((mouseX - offsetX) / (cellSize * zoom));
        const y = Math.floor((mouseY - offsetY) / (cellSize * zoom));
        copyEnd = { x, y };
        render();
        return;
    }

    if (isDragging && draggedEntity) {
        const worldX = (mouseX - offsetX) / (cellSize * zoom);
        const worldY = (mouseY - offsetY) / (cellSize * zoom);
        draggedEntity.x = Math.max(0.5, Math.min(mapData.metadata.width - 0.5, worldX));
        draggedEntity.y = Math.max(0.5, Math.min(mapData.metadata.height - 0.5, worldY));
        render();
        return;
    }

    if (isDragging && draggedTile) {
        const x = Math.floor((mouseX - offsetX) / (cellSize * zoom));
        const y = Math.floor((mouseY - offsetY) / (cellSize * zoom));
        if (x !== draggedTile.x || y !== draggedTile.y) {
            const layer = getTileLayer();
            const oldIdx = draggedTile.y * mapData.metadata.width + draggedTile.x;
            const newIdx = y * mapData.metadata.width + x;
            if (newIdx >= 0 && newIdx < layer.data.length && layer.data[newIdx] === 0) {
                layer.data[oldIdx] = 0;
                layer.data[newIdx] = draggedTile.originalTile;
                draggedTile.x = x;
                draggedTile.y = y;
                render();
            }
        }
        return;
    }

    if (e.buttons === 1 && currentTool === 'draw' && !isDragging) {
        const x = Math.floor((mouseX - offsetX) / (cellSize * zoom));
        const y = Math.floor((mouseY - offsetY) / (cellSize * zoom));
        setTile(x, y, selectedTile);
        render();
    }

    canvas.style.cursor = currentTool === 'pan' ? 'grab' : 'crosshair';

    const x = (mouseX - offsetX) / (cellSize * zoom);
    const y = (mouseY - offsetY) / (cellSize * zoom);
    const tileX = Math.floor(x);
    const tileY = Math.floor(y);

    const entity = findEntityAt(x, y);
    const layer = getTileLayer();
    const tileId = layer.data[tileY * mapData.metadata.width + tileX];
    const tileset = mapData.tilesets.find(t => t.id === tileId);

    if (entity || tileset) {
        tooltip.style.display = 'block';
        tooltip.style.left = e.clientX + 10 + 'px';
        tooltip.style.top = e.clientY + 10 + 'px';
        if (entity) {
            tooltip.textContent = `${entity.type}`;
        } else if (tileset) {
            tooltip.textContent = `${tileset.properties?.kind || 'tile'} - ${tileset.name}`;
        }
    } else {
        tooltip.style.display = 'none';
    }
}

function handleCanvasUp() {
    isPanning = false;

    if (isDragging && currentTool === 'copy' && copyStart && copyEnd) {
        copyRegion();
        isDragging = false;
    }

    if (isDragging && draggedEntity) {
        updateEntityList();
        showProperties();
        isDragging = false;
        draggedEntity = null;
    }

    if (isDragging && draggedTile) {
        isDragging = false;
        draggedTile = null;
    }
}

function setTile(x, y, tileId) {
    const layer = getTileLayer();
    const idx = y * mapData.metadata.width + x;
    if (idx >= 0 && idx < layer.data.length) {
        layer.data[idx] = tileId;
    }
}

function addEntity(x, y) {
    const type = document.getElementById('entity-type').value;

    if (type === 'player_spawn' && entities.some(e => e.type === 'player_spawn')) {
        alert('只能有一个玩家出生点');
        return;
    }

    const newEntity = {
        id: Date.now(),
        type: type,
        x: x,
        y: y,
        properties: { ...(entityDefaults[type] || {}) }
    };
    entities.push(newEntity);
    selectedEntity = newEntity;
    syncEntityLayer();
    updateEntityTypeOptions();
    updateEntityList();
    showProperties();
}

function selectEntityAt(x, y) {
    selectedEntity = findEntityAt(x, y);
    updateEntityList();
    showProperties();
}

function updateEntityList() {
    const list = document.getElementById('entity-list');
    list.innerHTML = '';
    entities.forEach(e => {
        const item = document.createElement('div');
        item.className = 'entity-item' + (e === selectedEntity ? ' selected' : '');
        item.textContent = `${e.type} (${e.x.toFixed(1)}, ${e.y.toFixed(1)})`;
        item.onclick = () => { selectedEntity = e; updateEntityList(); showProperties(); render(); };
        list.appendChild(item);
    });
}

function showProperties() {
    const props = document.getElementById('properties');
    if (!selectedEntity) {
        props.innerHTML = '<p>未选择实体</p>';
        return;
    }

    const entityProps = selectedEntity.properties || {};
    const fields = [];

    if (selectedEntity.type === 'player_spawn') {
        fields.push(
            { key: 'angle', label: '角度', step: '1' },
            { key: 'pitch', label: '俯仰', step: '1' },
            { key: 'fov', label: 'FOV', step: '1' },
            { key: 'height', label: '视点高度', step: '0.01' },
            { key: 'bobAmount', label: '摆动幅度', step: '0.01' },
            { key: 'bobSpeed', label: '摆动速度', step: '0.1' }
        );
    }
    if (selectedEntity.type === 'table') {
        fields.push(
            { key: 'width', label: '宽度', step: '0.1' },
            { key: 'depth', label: '深度', step: '0.1' },
            { key: 'topHeight', label: '桌面高度', step: '0.01' },
            { key: 'thickness', label: '桌板厚度', step: '0.01' },
            { key: 'legThickness', label: '桌腿粗细', step: '0.01' },
            { key: 'desc', label: '调查标题', type: 'text' },
            { key: 'detail', label: '调查描述', type: 'textarea' }
        );
    }
    if (selectedEntity.type === 'pyramid') {
        fields.push(
            { key: 'size', label: '底面尺寸', step: '0.01' },
            { key: 'height', label: '高度', step: '0.01' },
            { key: 'desc', label: '调查标题', type: 'text' },
            { key: 'detail', label: '调查描述', type: 'textarea' }
        );
    }
    if (selectedEntity.type === 'point_light') {
        fields.push(
            { key: 'color', label: '颜色', type: 'text' },
            { key: 'intensity', label: '强度', step: '0.01' },
            { key: 'radius', label: '半径(m)', step: '0.1' },
            { key: 'height', label: '高度(m)', step: '0.01' },
            { key: 'pulseAmount', label: '脉动幅度', step: '0.01' },
            { key: 'pulseSpeed', label: '脉动速度', step: '0.01' },
            { key: 'phase', label: '相位', step: '0.01' }
        );
    }
    if (selectedEntity.type === 'statue_sprite') {
        fields.push(
            { key: 'desc', label: '调查标题', type: 'text' },
            { key: 'detail', label: '调查描述', type: 'textarea' }
        );
    }

    if (fields.length === 0) {
        Object.keys(entityProps).forEach(key => {
            fields.push({
                key,
                label: key,
                step: '0.01',
                type: typeof entityProps[key] === 'number' ? 'number' : 'text'
            });
        });
    }

    const dynamicInputs = fields.map(field => {
        const value = entityProps[field.key] ?? '';
        const inputType = field.type || 'number';
        if (inputType === 'textarea') {
            return `<label>${field.label}: <textarea class="entity-prop-input" data-prop-key="${field.key}" rows="4">${escapeHtml(value)}</textarea></label>`;
        }
        return `<label>${field.label}: <input type="${inputType}" class="entity-prop-input" data-prop-key="${field.key}" value="${escapeHtml(value)}" step="${field.step}"></label>`;
    }).join('');

    props.innerHTML = `<p><strong>${selectedEntity.type}</strong></p>
        <label>X: <input type="number" id="prop-x" value="${escapeHtml(selectedEntity.x)}" step="0.1"></label>
        <label>Y: <input type="number" id="prop-y" value="${escapeHtml(selectedEntity.y)}" step="0.1"></label>
        ${dynamicInputs}
        <button onclick="updateEntityProps()">更新</button>
        <button onclick="deleteEntity()">删除</button>`;
}

function updateEntityProps() {
    if (selectedEntity) {
        saveHistory();
        selectedEntity.x = parseFloat(document.getElementById('prop-x').value);
        selectedEntity.y = parseFloat(document.getElementById('prop-y').value);
        selectedEntity.properties = selectedEntity.properties || {};
        document.querySelectorAll('.entity-prop-input').forEach(input => {
            const value = input.value;
            const isNumeric = input.tagName !== 'TEXTAREA' && input.type === 'number';
            selectedEntity.properties[input.dataset.propKey] = isNumeric
                ? parseFloat(value)
                : value;
        });
        syncEntityLayer();
        updateEntityList();
        showProperties();
        render();
    }
}

function deleteEntity() {
    if (selectedEntity) {
        saveHistory();
        entities = entities.filter(e => e !== selectedEntity);
        syncEntityLayer();
        selectedEntity = null;
        updateEntityTypeOptions();
        updateEntityList();
        showProperties();
        render();
    }
}

function saveHistory() {
    const state = {
        data: [...getTileLayer().data],
        entities: JSON.parse(JSON.stringify(entities))
    };
    history = history.slice(0, historyIndex + 1);
    history.push(state);
    historyIndex++;
    if (history.length > 50) {
        history.shift();
        historyIndex--;
    }
}

function resetHistory() {
    history = [];
    historyIndex = -1;
    saveHistory();
}

function undo() {
    if (historyIndex > 0) {
        historyIndex--;
        const state = history[historyIndex];
        getTileLayer().data = [...state.data];
        entities = JSON.parse(JSON.stringify(state.entities));
        syncEntityLayer();
        updateEntityTypeOptions();
        updateEntityList();
        render();
    }
}

function redo() {
    if (historyIndex < history.length - 1) {
        historyIndex++;
        const state = history[historyIndex];
        getTileLayer().data = [...state.data];
        entities = JSON.parse(JSON.stringify(state.entities));
        syncEntityLayer();
        updateEntityTypeOptions();
        updateEntityList();
        render();
    }
}

function copyRegion() {
    const x1 = Math.min(copyStart.x, copyEnd.x);
    const y1 = Math.min(copyStart.y, copyEnd.y);
    const x2 = Math.max(copyStart.x, copyEnd.x);
    const y2 = Math.max(copyStart.y, copyEnd.y);
    const w = x2 - x1 + 1;
    const h = y2 - y1 + 1;

    copiedData = { width: w, height: h, tiles: [] };
    const layer = getTileLayer();

    for (let y = y1; y <= y2; y++) {
        for (let x = x1; x <= x2; x++) {
            copiedData.tiles.push(layer.data[y * mapData.metadata.width + x]);
        }
    }

    currentTool = 'paste';
}

function pasteRegion(x, y) {
    if (!copiedData) return;
    saveHistory();
    const layer = getTileLayer();

    for (let dy = 0; dy < copiedData.height; dy++) {
        for (let dx = 0; dx < copiedData.width; dx++) {
            const tx = x + dx;
            const ty = y + dy;
            if (tx >= 0 && tx < mapData.metadata.width && ty >= 0 && ty < mapData.metadata.height) {
                layer.data[ty * mapData.metadata.width + tx] = copiedData.tiles[dy * copiedData.width + dx];
            }
        }
    }
}

function render() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    ctx.save();
    ctx.translate(offsetX, offsetY);
    ctx.scale(zoom, zoom);

    const layer = getTileLayer();
    for (let y = 0; y < mapData.metadata.height; y++) {
        for (let x = 0; x < mapData.metadata.width; x++) {
            const tileId = layer.data[y * mapData.metadata.width + x];
            ctx.fillStyle = getTileColor(tileId);
            ctx.fillRect(x * cellSize, y * cellSize, cellSize, cellSize);
            ctx.strokeStyle = '#333';
            ctx.strokeRect(x * cellSize, y * cellSize, cellSize, cellSize);
        }
    }

    entities.forEach(e => {
        if (e.type === 'table') {
            const widthMeters = Number(e.properties?.width || entityDefaults.table.width);
            const depthMeters = Number(e.properties?.depth || entityDefaults.table.depth);
            const width = metersToCells(widthMeters) * cellSize;
            const depth = metersToCells(depthMeters) * cellSize;
            ctx.fillStyle = 'rgba(155, 106, 71, 0.55)';
            ctx.fillRect(e.x * cellSize - width * 0.5, e.y * cellSize - depth * 0.5, width, depth);
            ctx.strokeStyle = '#f3d6b3';
            ctx.strokeRect(e.x * cellSize - width * 0.5, e.y * cellSize - depth * 0.5, width, depth);
            ctx.fillStyle = '#fff5df';
            ctx.font = '12px Arial';
            ctx.fillText(
                `${widthMeters.toFixed(2)}m x ${depthMeters.toFixed(2)}m`,
                e.x * cellSize - width * 0.5,
                e.y * cellSize - depth * 0.5 - 6
            );
        } else if (e.type === 'pyramid') {
            const sizeMeters = Number(e.properties?.size || entityDefaults.pyramid.size);
            const size = metersToCells(sizeMeters) * cellSize;
            const half = size * 0.5;
            ctx.fillStyle = 'rgba(215, 181, 86, 0.60)';
            ctx.beginPath();
            ctx.moveTo(e.x * cellSize, e.y * cellSize - half);
            ctx.lineTo(e.x * cellSize + half, e.y * cellSize);
            ctx.lineTo(e.x * cellSize, e.y * cellSize + half);
            ctx.lineTo(e.x * cellSize - half, e.y * cellSize);
            ctx.closePath();
            ctx.fill();
            ctx.strokeStyle = '#fff0b8';
            ctx.stroke();
            ctx.fillStyle = '#fff0b8';
            ctx.font = '12px Arial';
            ctx.fillText(
                `${sizeMeters.toFixed(2)}m`,
                e.x * cellSize - half,
                e.y * cellSize - half - 6
            );
        } else if (e.type === 'point_light') {
            const radiusMeters = Number(e.properties?.radius || entityDefaults.point_light.radius);
            const radius = metersToCells(radiusMeters) * cellSize;
            const color = e.properties?.color || entityDefaults.point_light.color;
            ctx.strokeStyle = color;
            ctx.fillStyle = color + '33';
            ctx.beginPath();
            ctx.arc(e.x * cellSize, e.y * cellSize, radius, 0, Math.PI * 2);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(e.x * cellSize, e.y * cellSize, radius, 0, Math.PI * 2);
            ctx.stroke();
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(e.x * cellSize, e.y * cellSize, 6, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = '#fff7d8';
            ctx.font = '12px Arial';
            ctx.fillText(
                `${radiusMeters.toFixed(1)}m / ${Number(e.properties?.intensity || entityDefaults.point_light.intensity).toFixed(2)}`,
                e.x * cellSize - radius,
                e.y * cellSize - radius - 6
            );
        } else {
            ctx.fillStyle = e.type === 'player_spawn' ? '#00ff00' : '#ffff00';
            ctx.beginPath();
            ctx.arc(e.x * cellSize, e.y * cellSize, 8, 0, Math.PI * 2);
            ctx.fill();
            if (e.type === 'player_spawn') {
                const angle = (Number(e.properties?.angle || entityDefaults.player_spawn.angle) * Math.PI) / 180;
                ctx.strokeStyle = '#ffffff';
                ctx.beginPath();
                ctx.moveTo(e.x * cellSize, e.y * cellSize);
                ctx.lineTo(
                    e.x * cellSize + Math.cos(angle) * 16,
                    e.y * cellSize + Math.sin(angle) * 16
                );
                ctx.stroke();
            }
        }
        if (e === selectedEntity) {
            ctx.strokeStyle = '#fff';
            ctx.lineWidth = 2;
            const bounds = getEntityBounds(e);
            ctx.strokeRect(
                bounds.minX * cellSize,
                bounds.minY * cellSize,
                (bounds.maxX - bounds.minX) * cellSize,
                (bounds.maxY - bounds.minY) * cellSize
            );
            ctx.lineWidth = 1;
        }
    });

    if (copyStart && currentTool === 'copy') {
        ctx.strokeStyle = '#00ffff';
        ctx.lineWidth = 2;
        if (copyEnd) {
            const x1 = Math.min(copyStart.x, copyEnd.x);
            const y1 = Math.min(copyStart.y, copyEnd.y);
            const x2 = Math.max(copyStart.x, copyEnd.x);
            const y2 = Math.max(copyStart.y, copyEnd.y);
            ctx.strokeRect(x1 * cellSize, y1 * cellSize, (x2 - x1 + 1) * cellSize, (y2 - y1 + 1) * cellSize);
        } else {
            ctx.strokeRect(copyStart.x * cellSize, copyStart.y * cellSize, cellSize, cellSize);
        }
    }

    ctx.restore();
}

async function saveMap() {
    syncEntityLayer();
    const json = JSON.stringify(mapData, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    downloadBlob(blob, currentMapName);

    try {
        const smapBlob = await buildSmapBlob();
        downloadBlob(smapBlob, getSmapName());
    } catch (error) {
        console.error(error);
        alert(`JSON 已导出，但 .smap 导出失败: ${error.message}`);
    }
}

function importMap(e) {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
        mapData = JSON.parse(ev.target.result);
        currentMapName = file.name;
        entities = getEntityLayer().objects;
        selectedEntity = null;
        document.getElementById('map-width').value = mapData.metadata.width;
        document.getElementById('map-height').value = mapData.metadata.height;
        updateCurrentMapLabel();
        updateTilePalette();
        updateEntityTypeOptions();
        updateEntityList();
        showProperties();
        resetHistory();
        centerMap();
        render();
    };
    reader.readAsText(file);
}

function resizeMap() {
    const newWidth = parseInt(document.getElementById('map-width').value);
    const newHeight = parseInt(document.getElementById('map-height').value);

    const layer = getTileLayer();
    const oldWidth = mapData.metadata.width;
    const oldHeight = mapData.metadata.height;
    const newData = new Array(newWidth * newHeight).fill(0);

    for (let y = 0; y < Math.min(oldHeight, newHeight); y++) {
        for (let x = 0; x < Math.min(oldWidth, newWidth); x++) {
            newData[y * newWidth + x] = layer.data[y * oldWidth + x];
        }
    }

    layer.data = newData;
    mapData.metadata.width = newWidth;
    mapData.metadata.height = newHeight;

    centerMap();
    render();
}

init();
