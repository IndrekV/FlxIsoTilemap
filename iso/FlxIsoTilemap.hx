package iso;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.frames.FlxFramesCollection;
import flixel.graphics.frames.FlxTileFrames;
import flixel.graphics.tile.FlxDrawTilesItem;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.system.FlxAssets.FlxTilemapGraphicAsset;
import haxe.xml.Fast;
import iso.IsoTile;
import iso.MapLayer;
import iso.Stack;
import openfl.Assets;
import openfl.display.Sprite;
import openfl.display.Tilesheet;
import openfl.events.Event;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
using StringTools;

/**
 * ...
 * @author Tiago Ling Alexandre
 */
class FlxIsoTilemap extends FlxObject
{
	public var map_w:Int;
	public var map_h:Int;
	
	//TODO: Substitute by Flixel's camera
	public var cameraScroll:FlxPoint;
	public var scale:FlxPoint;
	public var layers:Array<iso.MapLayer>;
	public var viewport:Sprite;
	
	var frameCollections:Array<FlxFramesCollection>;
	var graphics:Array<FlxGraphic>;
	
	//Draw helpers
	var matrix:flixel.math.FlxMatrix;
	var offset:flixel.math.FlxPoint;
	var frame:FlxFrame;
	var drawItem:FlxDrawTilesItem;
	
	var viewportBounds:Rectangle;
	var offsetViewportBounds:Rectangle;
	
	var tile_gfx_width:Float;
	var tile_gfx_height:Float;
	var height_gfx_offset:Float;
	
	//TODO: Make properties out of these
	public var tile_width:Float;
	public var tile_height:Float;
	public var height_offset:Float;
	public var origin:FlxPoint;
	
	//Viewport size, used for tile culling
	var viewportWidth:Float;
	var viewportHeight:Float;
	var topLeft:FlxPoint;
	var topRight:FlxPoint;
	var botLeft:FlxPoint;
	var botRight:FlxPoint;
	var map_pixel_width:Float;
	var map_pixel_height:Float;
	
	public function new(viewport:FlxPoint, tileSize:FlxPoint, tileHeightOffset:Float) 
	{
		super();
		
		viewportWidth = viewport.x;
		viewportHeight = viewport.y;
		
		tile_width = tile_gfx_width = tileSize.x;
		tile_height = tile_gfx_height = tileSize.y;
		height_offset = height_gfx_offset = tileHeightOffset;
		
		cameraScroll = new FlxPoint();
		scale = new FlxPoint(1, 1);
		
		layers = new Array<iso.MapLayer>();
		frameCollections = new Array<FlxFramesCollection>();
		graphics = new Array<FlxGraphic>();
	}
	
	public function init(sizeInTiles:FlxPoint)
	{
		map_w = Std.int(sizeInTiles.x);
		map_h = Std.int(sizeInTiles.y);
		
		//Map size in pixels, used to calculate origin and bounds
		map_pixel_width = map_h * tile_width + ((map_w - map_h) * (tile_height - height_offset));
		map_pixel_height = map_w * (tile_height - height_offset) + ((map_h - map_w) * (tile_height - height_offset) / 2);
		
		//Calculating origin so the map is always centered on the screen (does not take into account walls (height_offset))
		var offset_x = map_pixel_width / 2 - tile_width / 2;
		origin = new FlxPoint(FlxG.stage.stageWidth / 2 - map_pixel_width / 2 + offset_x, FlxG.stage.stageHeight / 2 - map_pixel_height / 2 - height_offset);
		
		//User-defined viewport
		viewportBounds = new Rectangle(FlxG.stage.stageWidth / 2 - viewportWidth / 2, FlxG.stage.stageHeight / 2 - viewportHeight / 2, viewportWidth, viewportHeight);
		
		//This is needed for mouse detection (TODO: fix)
/*		viewport = new Sprite();
		FlxG.stage.addChild(viewport);
		
		var gfx = viewport.graphics;
		gfx.beginFill(0x0, 0);
		gfx.drawRect(0, 0, viewportWidth, viewportHeight);
		gfx.endFill();*/
		
		//Actual viewport, used with offset to correctly perform the culling
		offsetViewportBounds = new Rectangle(viewportBounds.x - tile_width,
											 viewportBounds.y - (tile_height - height_offset),
											 viewportBounds.width + 2 * tile_width,
											 viewportBounds.height + 2 * (tile_height - height_offset) + height_offset);	//Add height_offset to account for the wall height at the bottom of the screen
		
		//Init draw helpers
		matrix = new FlxMatrix();
		offset = new FlxPoint();
	}
	
	override public function update(elapsed:Float):Void
	{
		updateViewport(elapsed);
	}
	
	public function updateViewport(elapsed:Float)
	{
		//Get all viewport corners
		topLeft = getScreenToIso(offsetViewportBounds.x - cameraScroll.x, offsetViewportBounds.y - cameraScroll.y);
		topRight = getScreenToIso(offsetViewportBounds.x + offsetViewportBounds.width - cameraScroll.x, offsetViewportBounds.y - cameraScroll.y);
		botLeft = getScreenToIso(offsetViewportBounds.x - cameraScroll.x, offsetViewportBounds.y + offsetViewportBounds.height - cameraScroll.y);
		botRight = getScreenToIso(offsetViewportBounds.x + offsetViewportBounds.width - cameraScroll.x, offsetViewportBounds.y + offsetViewportBounds.height - cameraScroll.y);
		
		var i_length:Int = Std.int(botLeft.y - topRight.y + 1);
		var i_start:Int = Std.int(topRight.y);
		
		for (k in 0...layers.length) {
			
			var j_start:Int = 0;
			var j_end:Int = 0;
			var alt_count:Int = 0;
			
			var layer = layers[k];
			if (layer == null) continue;
			layer.viewportTiles.splice(0, layer.viewportTiles.length);
			
			for (i in 0...i_length) {
				
				if (i < i_length / 2) {
					j_start = Std.int(topRight.x - i);
					j_end = Std.int(topRight.x + i);
				} else {
					alt_count++;
					j_start = Std.int(topLeft.x + alt_count);
					j_end = Std.int(botRight.x - alt_count + 1);
				}
				
				var j_length:Int = (j_end - j_start) + 1;
				for (j in 0...j_length) {
					var tX:Int = j_start + j;
					var tY:Int = i_start + i;
					
					if (tX < 0 || tX >= map_w || tY < 0 || tY >= map_h)
						continue;
					
					var stack = layer.stacks[tY][tX];
					
					if (stack == null) continue;
					if (stack.length == 1 && stack.root.type == -1)
						continue;
					
					//Experimental: Tile animation update
/*					for (l in 0...stack.length) {
						var tile = stack.get(l);
						
						if (tile == null) continue;
						
						if (tile.animated)
							tile.updateAnimation(1 / 60);
					}*/
					
					layer.viewportTiles.push(stack);
				}
			}
			
			if (layer.isDynamic)
				layer.update(elapsed);
		}
	}
	
	override public function draw():Void
	{
		drawViewport(cameras[0]);
	}
	
	public function drawViewport(Camera:FlxCamera)
	{
		for (k in 0...layers.length) {
			var layer = layers[k];
			var count:Int = 0;
			
			drawItem = Camera.startQuadBatch(graphics[layer.tilesetId], false, false, null, false);
			
			for (i in 0...layer.viewportTiles.length) {
				var stack = layer.viewportTiles[i];
				
				for (j in 0...stack.length) {
					
					var tile = stack.get(j);
					if (tile == null || tile.type == -1 ) continue;
					
					//Experimental: draw shadows
					if (tile.hasShadow) {
						matrix.identity();
						
						//Translate to tile pivot
						matrix.translate(-tile_width / 2, -80);
						
						//Apply transformations (scale, rotate, skew)
						matrix.scale(tile.shadowScale, tile.shadowScale);
						
						//Translate back from tile pivot
						matrix.translate(tile_width / 2, 80);
						
						//TODO: Fix global scale positioning of shadow
						matrix.translate(origin.x + (tile.x * scale.x) + Std.int(cameraScroll.x), origin.y + (tile.y * scale.y) + Std.int(cameraScroll.y));
						
						var shadowFrame = frameCollections[layer.tilesetId].getByIndex(tile.shadowId);
						drawItem.addQuad(shadowFrame, matrix, null);
					}
					
					var collection = frameCollections[layer.tilesetId];
					frame = frameCollections[layer.tilesetId].getByIndex(tile.type);
					
					//Tile matrix
					//When flipping we must add the tile width / height
					offset.set(tile.facing.x < 0 ? tile_width : 0, tile.facing.y < 0 ? tile_height : 0);
					
					matrix.identity();
					
					matrix.translate(-tile_width / 2, -80);
					matrix.scale(scale.x * tile.facing.x, scale.y * tile.facing.y);
					matrix.translate(tile_width / 2, 80);
					matrix.translate(origin.x + tile.x + Std.int(cameraScroll.x), origin.y + (tile.y - tile.z) + Std.int(cameraScroll.y));
					
					drawItem.addQuad(frame, matrix, null);
				}
			}
		}
	}
	
	public function addTileset(gfx:FlxTilemapGraphicAsset, tileWidth:Int, tileHeight:Int):Int
	{
		if (Std.is(gfx, FlxFramesCollection))
		{
			frameCollections.push(cast gfx);
			graphics.push(cast(gfx, FlxFramesCollection).parent);
			return frameCollections.length - 1;
		}
		
		var graph:FlxGraphic = FlxG.bitmap.add(cast gfx);
		if (graph == null)
		{
			return -1;
		}
		
		// Figure out the size of the tiles
		tile_width = tileWidth;
		if (tile_width <= 0)
		{
			tile_width = graph.height;
		}
		
		tile_height = tileHeight;
		if (tile_height <= 0)
		{
			tile_height = tile_width;
		}
		
		frameCollections.push(FlxTileFrames.fromGraphic(graph, new FlxPoint(tile_width, tile_height)));
		graphics.push(graph);
		
		return frameCollections.length - 1;
	}
	
	public function addLayer(layer:MapLayer)
	{
		layer.map = this;
		layers.push(layer);
	}
	
	public function getTilesetGraphic(id:Int):FlxGraphic
	{
		return graphics[id];
	}
	
	public function addSpriteAtTilePos(sprite:FlxSprite, layer:Int, r:Int, c:Int)
	{
		layers[layer].addSpriteAtTilePos(sprite, r, c);
	}
	
	public function addSpriteAtWorldPos(sprite:FlxSprite, layer:Int, x:Float, y:Float)
	{
		layers[layer].addSpriteAtWorldPos(sprite, x, y);
	}
	
	public function getScreenToIso(screen_x:Float, screen_y:Float, offset:FlxPoint = null, asInt:Bool = true):FlxPoint
	{
		var cX = screen_x - origin.x - (tile_height - height_offset);
		var cY = screen_y - origin.y - tile_width;
		
		if (offset != null) {
			//Camera offset (interferes with positioning)
			cX -= offset.x;
			cY -= offset.y;
		}
		
		if (asInt) {
			var mapX:Int = Std.int((cX / (tile_width / 2) + cY / ((tile_height - height_offset) / 2)) / 2);
			var mapY:Int = Std.int((cY / ((tile_height - height_offset) / 2) - cX / (tile_width / 2)) / 2);
			return new FlxPoint(mapX, mapY);
		} else {
			var mapX:Float = (cX / (tile_width / 2) + cY / ((tile_height - height_offset) / 2)) / 2;
			var mapY:Float = (cY / ((tile_height - height_offset) / 2) - cX / (tile_width / 2)) / 2;
			return new FlxPoint(mapX, mapY);
		}
	}
	
	public function getIsoToScreen(iso_x:Float, iso_y:Float, offset:FlxPoint = null):FlxPoint
	{
		var cX = (iso_x - iso_y) * tile_width / 2;
		var cY = (iso_x + iso_y) * ((tile_height - height_offset) / 2);
		
		cX += origin.x + (tile_height - height_offset);
		cY += origin.y + tile_width;
		
		if (offset != null) {
			//Camera offset (interferes with positioning)
			cX += offset.x;
			cY += offset.y;
		}
		
		return new FlxPoint(cX, cY);
	}
	
	public function getWorldToScreen(world_x:Float, world_y:Float):FlxPoint
	{
		return new FlxPoint(world_x + origin.x + (tile_height - height_offset), world_y + origin.y + tile_width);
	}
	
	public function updateScale(newScale:Float)
	{
		tile_width = tile_gfx_width * scale.x;
		tile_height = tile_gfx_height * scale.y;
		height_offset = height_gfx_offset * scale.y;
		
		//Map size in pixels, used to calculate origin and bounds
		var map_pixel_width = map_h * tile_width + ((map_w - map_h) * (tile_height - height_offset));
		var map_pixel_height = map_w * (tile_height - height_offset) + ((map_h - map_w) * (tile_height - height_offset) / 2);
		
		//Calculating origin so the map is always centered on the screen (does not take into account walls (height_offset))
		var offset_x = map_pixel_width / 2 - tile_width / 2;
		origin = new FlxPoint(FlxG.stage.stageWidth / 2 - map_pixel_width / 2 + offset_x, FlxG.stage.stageHeight / 2 - map_pixel_height / 2 - height_offset);
		
		//Actual viewport, used with offset to correctly perform the culling
		offsetViewportBounds = new Rectangle(viewportBounds.x - tile_width,
											 viewportBounds.y - (tile_height - height_offset),
											 viewportBounds.width + 2 * tile_width,
											 viewportBounds.height + 2 * (tile_height - height_offset) + height_offset);	//Add height_offset to account for the wall height at the bottom of the screen
	}
	
	public function getBounds():Rectangle
	{
		//Tilemap Bounding rectangle, yellow (includes height_offset for walls)
		return new Rectangle(origin.x - (map_h - 1) * tile_width / 2, origin.y, map_pixel_width, map_pixel_height + height_offset);
	}
}