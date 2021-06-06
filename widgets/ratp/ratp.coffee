class Dashing.Ratp extends Dashing.Widget
  onData: (data) ->
    for result in data.results
      transportId = result.key
      currentResult = result.value
      
      transportId1 = transportId + '-1'
      transportId2 = transportId + '-2'

      element = $("##{transportId}-1").val()
      if not element?
        # First time, build the table

        @createRow(currentResult.type, currentResult.id, transportId1)
          .insertBefore($('.widget-ratp #placeholder'))
        @createRow(currentResult.type, currentResult.id, transportId2)
          .insertBefore($('.widget-ratp #placeholder'))

      @update(transportId1, currentResult.d1, currentResult.t1, currentResult.status)
      @update(transportId2, currentResult.d2, currentResult.t2, currentResult.status)

  createRow: (type, id, transportId) ->
    cellIcon = $ '<span>'
    cellIcon.addClass 'transport'
    cellIcon.attr 'id', transportId + '-icon'

    imgIcon = $ '<img>'
    imgIcon.attr 'src', "https://www.ratp.fr/sites/default/files/network/#{type}/ligne#{id}.svg"
    imgIcon.addClass type
    imgIcon.addClass 'icon'
    imgIcon.on 'error', ->
      console.log "Unable to retrieve #{imgIcon.attr 'src'}"
      cellIcon.html id # If image is not available, fall back to text

    cellIcon.append imgIcon

    cellDest = $ '<span>'
    cellDest.addClass 'dest'
    cellDest.attr 'id', transportId + '-dest'

    cellTime = $ '<span>'
    cellTime.addClass 'time'
    cellTime.attr 'id', transportId + '-time'

    row = $ '<div>'
    row.attr 'id', transportId
    row.addClass 'item'
    row.append cellIcon
    row.append cellDest
    row.append cellTime

    return row

  update: (id, newDest, newTime, status) ->
    @iconUpdate(id, status)
    @fadeUpdate(id, 'dest', newDest)
    @fadeUpdate(id, 'time', newTime)

  iconUpdate: (id, status) ->
    iconId = "##{id}-icon"
    if status == 'critical'
      $(iconId).addClass 'critical'
    else
      $(iconId).removeClass 'critical'

    if status == 'alerte'
      $(iconId).addClass 'alert'
    else
      $(iconId).removeClass 'alert'

  fadeUpdate: (id, type, newValue) ->
    spanId = "##{id}-#{type}"
  
    if newValue == '[ND]'
      $(spanId).addClass 'grayed'
    else
      $(spanId).removeClass 'grayed'

      oldValue = $(spanId).html()

      if oldValue != newValue
        $(spanId).fadeOut(->
          if type == 'time'
            if !(newValue.includes ' mn') && !(newValue.match /\d{1,2}:\d{1,2}/)
              $(spanId).addClass 'condensed'
            else
              $(spanId).removeClass 'condensed'

          $(this).html(newValue).fadeIn()
        )

    
