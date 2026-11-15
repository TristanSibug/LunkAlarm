package online.reeeserve.lunkalarm.core

import kotlin.random.Random

enum class StroopColor(val label: String) { RED("Red"), BLUE("Blue"), GREEN("Green"), YELLOW("Yellow") }

data class StroopRound(val word: StroopColor, val ink: StroopColor, val buttonColors: List<StroopColor>) {
    fun validate() {
        require(word != ink && buttonColors.size == StroopColor.entries.size && buttonColors.toSet().size == StroopColor.entries.size)
        require(StroopColor.entries.zip(buttonColors).all { (label, background) -> label != background })
    }
    companion object {
        fun create(previousInk: StroopColor? = null, random: Random = Random.Default): StroopRound {
            val colors = StroopColor.entries
            val ink = colors.filter { it != previousInk }.random(random)
            val word = colors.filter { it != ink }.random(random)
            val offset = random.nextInt(1, colors.size)
            return StroopRound(word, ink, colors.indices.map { colors[(it + offset) % colors.size] })
        }
    }
}
