package com.miniradio.car;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class StationQueue {
    static final int DISCOVER = 0, FAVORITES = 1, RECENT = 2;
    int tab = DISCOVER;
    private String query = "";
    final List<Station> stations = new ArrayList<>();

    void update(int selectedTab, String filter, List<Station> visible) {
        Map<String, Station> incoming = new LinkedHashMap<>();
        for (Station station : visible) incoming.put(station.id, station);
        List<Station> ordered = new ArrayList<>();
        if (selectedTab == RECENT && tab == RECENT && query.equals(filter)) {
            // Listening moves a record to the front of storage. Keep the displayed
            // traversal order so repeated next presses can visit the whole list.
            for (Station previous : stations) {
                Station current = incoming.remove(previous.id);
                if (current != null) ordered.add(current);
            }
        }
        stations.clear(); stations.addAll(incoming.values()); stations.addAll(ordered);
        tab = selectedTab; query = filter;
    }

    Station adjacent(Station current, int direction) {
        int index = -1;
        for (int i = 0; i < stations.size(); i++) if (current != null && stations.get(i).id.equals(current.id)) index = i;
        int next = MediaButtons.adjacentIndex(index, stations.size(), direction);
        return next < 0 ? null : stations.get(next);
    }

    static Station random(List<Station> stations, Station current, java.util.Random random) {
        List<Station> alternatives = new ArrayList<>(stations);
        if (alternatives.size() > 1 && current != null) alternatives.removeIf(item -> item.id.equals(current.id));
        return alternatives.isEmpty() ? null : alternatives.get(random.nextInt(alternatives.size()));
    }
}
