package com.medipos.medipos

import android.content.Context
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.ResourceBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import androidx.concurrent.futures.ResolvableFuture
import androidx.wear.tiles.LayoutElementBuilders
import androidx.wear.tiles.TimelineBuilders
import androidx.wear.tiles.ColorBuilders
import androidx.wear.tiles.DimensionBuilders

class WearSummaryTileService : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> {
        val future = ResolvableFuture.create<TileBuilders.Tile>()
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val revenue = prefs.getString("flutter.today_revenue", "₹0") ?: "₹0"
        val count = prefs.getInt("flutter.today_count", 0)
        
        // Build a pure Column layout
        val rootLayout = LayoutElementBuilders.Column.Builder()
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText("TODAY'S REVENUE")
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(DimensionBuilders.SpProp.Builder().setValue(12f).build())
                            .setColor(
                                ColorBuilders.ColorProp.Builder()
                                    .setArgb(0xFF81C784.toInt())
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .addContent(
                LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.DpProp.Builder().setValue(8f).build()).build()
            )
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText(revenue)
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(DimensionBuilders.SpProp.Builder().setValue(24f).build())
                            .setColor(
                                ColorBuilders.ColorProp.Builder()
                                    .setArgb(0xFFFFFFFF.toInt())
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .addContent(
                LayoutElementBuilders.Spacer.Builder().setHeight(DimensionBuilders.DpProp.Builder().setValue(4f).build()).build()
            )
            .addContent(
                LayoutElementBuilders.Text.Builder()
                    .setText("$count Transactions")
                    .setFontStyle(
                        LayoutElementBuilders.FontStyle.Builder()
                            .setSize(DimensionBuilders.SpProp.Builder().setValue(12f).build())
                            .setColor(
                                ColorBuilders.ColorProp.Builder()
                                    .setArgb(0xFFB0BEC5.toInt())
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .build()

        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion("1")
            .setTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(
                        TimelineBuilders.TimelineEntry.Builder()
                            .setLayout(
                                LayoutElementBuilders.Layout.Builder()
                                    .setRoot(rootLayout)
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .build()
            
        future.set(tile)
        return future
    }
    
    override fun onResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> {
        val future = ResolvableFuture.create<ResourceBuilders.Resources>()
        val resources = ResourceBuilders.Resources.Builder()
            .setVersion("1")
            .build()
        future.set(resources)
        return future
    }
}
